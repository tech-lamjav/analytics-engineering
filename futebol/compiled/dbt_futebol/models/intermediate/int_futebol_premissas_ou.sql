

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- Universo de linhas: canônicas (toda fixture, p/ validar mesmo sem odds) + linhas reais
-- das odds (market_id=5, p/ a penalidade linha_extrema pegar 0,5 / 4,5 / 5,5 etc.).
canonical_lines AS (
    SELECT f.fixture_id, l AS line_value
    FROM fixtures f, UNNEST([1.5, 2.5, 3.5]) AS l
),
market_lines AS (
    SELECT DISTINCT fixture_id, line_value
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    WHERE market_id = 5 AND line_value IS NOT NULL
),
lines AS (
    SELECT fixture_id, line_value FROM canonical_lines
    UNION DISTINCT
    SELECT fixture_id, line_value FROM market_lines
),

-- 2 outcomes (Over/Under) por (fixture, linha), com o eixo do jogo (mandante/visitante).
outcomes AS (
    SELECT
        l.fixture_id, f.competition, f.competition_id, f.season, f.kickoff_utc,
        f.home_team_id, f.away_team_id,
        l.line_value, side AS outcome
    FROM lines l
    JOIN fixtures f USING (fixture_id)
    CROSS JOIN UNNEST(['Over', 'Under']) AS side
),

-- Correção da Task 0 (look-ahead): agregados POINT-IN-TIME por (fixture, time), só com jogos
-- anteriores ao kickoff, no lugar de fact_team_season_stats (1 snapshot por season = temporada
-- fechada em 24/25, com o próprio jogo e os seguintes dentro das médias).
pit AS (
    SELECT
        fixture_id, team_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        clean_sheet_total, failed_to_score_total, played_total
    FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`
),

-- Spine (fixture-alvo, time) p/ ancorar xG e ritmo ao kickoff — MESMO padrão que o _1x2 já
-- usava p/ o xG. Correção da Task 0 (item C): antes eram médias da season INTEIRA, o que fazia
-- o mesmo xG medir negativo no 1X2 (point-in-time) e positivo no Gols (contaminado).
fixture_team_spine AS (
    SELECT fixture_id, season, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, season, competition_id, kickoff_utc, away_team_id FROM fixtures
),

-- xG médio de ATAQUE do time ATÉ o jogo (Brasileirão preenchido, Copa ~vazio -> NULL ->
-- premissa de xG não dispara).
xg AS (
    SELECT sp.fixture_id, sp.team_id, SAFE_DIVIDE(SUM(CAST(st.expected_goals AS NUMERIC)), COUNT(st.expected_goals)) AS xg_for_avg
    FROM fixture_team_spine sp
    JOIN `smartbetting-dados`.`futebol`.`fact_fixture_stats` st
        ON  st.team_id        = sp.team_id
        AND st.season         = sp.season
        AND st.competition_id = sp.competition_id
        AND st.date_utc       < DATE(sp.kickoff_utc)
    GROUP BY sp.fixture_id, sp.team_id
),

-- Ritmo: finalizações+escanteios por time-jogo -> média do time ATÉ o jogo.
pace_team AS (
    SELECT sp.fixture_id, sp.team_id, sp.competition_id, sp.season,
           SAFE_DIVIDE(SUM(st.total_shots + st.corner_kicks), COUNT(st.total_shots + st.corner_kicks)) AS pace_avg
    FROM fixture_team_spine sp
    JOIN `smartbetting-dados`.`futebol`.`fact_fixture_stats` st
        ON  st.team_id        = sp.team_id
        AND st.season         = sp.season
        AND st.competition_id = sp.competition_id
        AND st.date_utc       < DATE(sp.kickoff_utc)
    GROUP BY sp.fixture_id, sp.team_id, sp.competition_id, sp.season
),
-- Mediana da liga sobre as médias por time NO INSTANTE DO JOGO: 1 mediana por (liga, season,
-- fixture), e não mais uma única mediana da season fechada.
-- ⚠️ A MEDIANA É `taskf_mediana`, E NÃO `APPROX_QUANTILES` (#78). Achado ao fechar a correção de
-- reprodutibilidade do xG: `ritmo_alto` acendeu em 16687/16690/16696/16699/16702 linhas em oito
-- execuções do MESMO SQL sobre o MESMO insumo — oscilação de ±15 linhas, ~5× a do xG, e por
-- MECANISMO DIFERENTE. Não é ponto flutuante: `APPROX_QUANTILES` é um SKETCH, e o resultado
-- depende de como a execução foi paralelizada. Este repositório já tinha medido isso na #57 (a
-- mediana de ppg do Brasileirão saiu 1,313 e depois 1,294 em execuções seguidas) e já tinha
-- escrito a cura — `macros/taskf_mediana.sql`, mediana exata por ordenação. O que faltava era
-- aplicá-la aqui: a cura ficou nas análises da task [F] e a produção seguiu com o sketch.
-- O `pace_avg` que entra aqui é determinístico (soma de INTEIROS em FLOAT64 é exata em qualquer
-- ordem); a instabilidade era toda da mediana. Custo da troca: ordena o pool por fixture em vez
-- de esboçá-lo, irrelevante no tamanho deste pool. Contrapartida declarada: para contagem par a
-- mediana passa a ser a INFERIOR dos dois centrais, e o valor é arredondado (o macro arredonda em
-- 3 casas por padrão) — as duas coisas declaradas, não descobertas.
league_pace_median AS (
    SELECT fixture_id,
           
    ROUND(
        ARRAY_AGG(pace_avg IGNORE NULLS ORDER BY pace_avg)
            [SAFE_OFFSET(DIV(COUNTIF((pace_avg) IS NOT NULL) - 1, 2))],
        3) AS pace_median
    FROM (
        SELECT sp.fixture_id, lt.team_id,
               SAFE_DIVIDE(SUM(st.total_shots + st.corner_kicks), COUNT(st.total_shots + st.corner_kicks)) AS pace_avg
        FROM (SELECT DISTINCT fixture_id, competition_id, season, kickoff_utc FROM fixture_team_spine) sp
        JOIN (SELECT DISTINCT competition_id, season, team_id FROM fixture_team_spine) lt
            ON lt.competition_id = sp.competition_id AND lt.season = sp.season
        JOIN `smartbetting-dados`.`futebol`.`fact_fixture_stats` st
            ON  st.team_id        = lt.team_id
            AND st.season         = sp.season
            AND st.competition_id = sp.competition_id
            AND st.date_utc       < DATE(sp.kickoff_utc)
        GROUP BY sp.fixture_id, lt.team_id
    )
    GROUP BY fixture_id
),

-- Histórico Over/Under: gols totais dos últimos 5 jogos FINALIZADOS de cada time, na MESMA
-- competição, MESMA season e ANTERIORES ao jogo. 1 array de totais por (fixture-alvo, time).
-- O filtro de season evita sangrar jogos da temporada passada através da pausa de off-season
-- (consistente com os joins de tss, que já são season-scoped).
finished AS (
    SELECT competition_id, season, kickoff_utc, home_team_id, away_team_id,
           goals_home + goals_away AS total_goals
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),
team_fixtures_long AS (
    SELECT home_team_id AS team_id, competition_id, season, kickoff_utc, total_goals FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, season, kickoff_utc, total_goals FROM finished
),
fixture_teams AS (
    SELECT fixture_id, competition_id, season, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc, away_team_id FROM fixtures
),
last5 AS (
    SELECT
        ft.fixture_id, ft.team_id,
        ARRAY_AGG(h.total_goals ORDER BY h.kickoff_utc DESC LIMIT 5) AS last5_totals
    FROM fixture_teams ft
    JOIN team_fixtures_long h
        ON h.team_id        = ft.team_id
       AND h.competition_id = ft.competition_id
       AND h.season         = ft.season
       AND h.kickoff_utc    < ft.kickoff_utc
    GROUP BY ft.fixture_id, ft.team_id
),

-- Movimento de linha = CONSENSO do mercado t24h -> t15m, por (fixture, linha, lado). Média de
-- PROBABILIDADES IMPLÍCITAS (1/odd) das casas, NÃO de odds cruas: a média de odds cruas
-- super-pondera o leg de odd alta (o Over em linhas altas) e enviesa o sinal pra um lado.
-- Distinto do sinal sharp (só Pinnacle) usado na corroboração.
line_move AS (
    SELECT
        fixture_id, line_value, outcome_side AS outcome,
        -- Mesma regra do resto do modelo (#78): sem `AVG`, e a soma em NUMERIC. Aqui a soma
        -- PRECISA ser em ponto fixo — `1.0 / odd_decimal` é fracionário, então somá-lo em FLOAT64
        -- voltaria a depender da ordem mesmo com SUM/COUNT no lugar de AVG (é por isso que o
        -- `pace_avg` pôde ficar em FLOAT64 e este não: lá a soma é de INTEIROS, e essa é exata).
        -- O CAST arredonda cada probabilidade implícita em 9 casas, folga de sobra p/ um número
        -- que vive perto de 0,5 e é comparado contra outro igual.
        SAFE_DIVIDE(
            SUM(  IF(collection_window = 't24h', CAST(1.0 / odd_decimal AS NUMERIC), NULL)),
            COUNT(IF(collection_window = 't24h', odd_decimal, NULL))) AS prob_t24h,
        SAFE_DIVIDE(
            SUM(  IF(collection_window = 't15m', CAST(1.0 / odd_decimal AS NUMERIC), NULL)),
            COUNT(IF(collection_window = 't15m', odd_decimal, NULL))) AS prob_t15m
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    WHERE market_id = 5 AND outcome_side IN ('Over', 'Under') AND odd_decimal > 0
    GROUP BY fixture_id, line_value, outcome_side
),

-- Métricas brutas derivadas (por outcome×linha).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.line_value,

        -- ataque combinado (mandante em casa + visitante fora) e defesas vazáveis
        h.goals_for_avg_home     + a.goals_for_avg_away      AS gf_comb,
        h.goals_against_avg_home + a.goals_against_avg_away   AS ga_comb,

        -- xG combinado (só Brasileirão)
        hx.xg_for_avg + ax.xg_for_avg                        AS xg_comb,

        -- ritmo: média do ritmo dos dois vs mediana da liga
        (hp.pace_avg + ap.pace_avg) / 2                      AS pace_both,
        lpm.pace_median                                       AS pace_median,

        -- clean sheet% / failed-to-score% por time (SAFE_DIVIDE p/ played_total=0)
        SAFE_DIVIDE(h.clean_sheet_total,     h.played_total) * 100 AS home_cs_pct,
        SAFE_DIVIDE(a.clean_sheet_total,     a.played_total) * 100 AS away_cs_pct,
        SAFE_DIVIDE(h.failed_to_score_total, h.played_total) * 100 AS home_fts_pct,
        SAFE_DIVIDE(a.failed_to_score_total, a.played_total) * 100 AS away_fts_pct,

        -- histórico Over/Under: quantos dos últimos 5 de cada bateram a linha.
        -- O IF na frente é a classe (b) do mapa (#41): COUNT sobre array VAZIO devolve 0 sem
        -- nenhum NULL para detectar, e esse zero é indistinguível de "cinco jogos, nenhum deles
        -- bateu". Sem histórico nenhum a contagem é desconhecida. O corte é em ZERO jogo, não em
        -- cinco: 1 a 4 jogos é medição real de amostra curta.
        IF(hl.last5_totals IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(hl.last5_totals) g WHERE g > o.line_value)) AS home_over_cnt,
        IF(al.last5_totals IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(al.last5_totals) g WHERE g > o.line_value)) AS away_over_cnt,
        IF(hl.last5_totals IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(hl.last5_totals) g WHERE g < o.line_value)) AS home_under_cnt,
        IF(al.last5_totals IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(al.last5_totals) g WHERE g < o.line_value)) AS away_under_cnt,

        -- movimento de consenso do lado deste outcome (Over ou Under): "linha caiu" = prob
        -- implícita média SUBIU (t15m > t24h) = odd caiu (dinheiro entrando neste lado).
        -- As duas probabilidades ficam expostas porque SÃO o insumo (#41, classe (c)): o
        -- COALESCE(..., FALSE) que ficava aqui colapsava "o mercado não se moveu" e "ainda não
        -- há t15m" num FALSE só — e numa janela distante o t15m não existe por construção, que
        -- é justamente o horizonte em que o contador precisa falar. O colapso continua, mas
        -- uma CTE adiante, onde a premissa é formada.
        lm.prob_t24h                                         AS prob_t24h,
        lm.prob_t15m                                         AS prob_t15m,
        (lm.prob_t15m > lm.prob_t24h)                        AS linha_caiu
    FROM outcomes o
    LEFT JOIN pit h  ON h.fixture_id  = o.fixture_id AND h.team_id  = o.home_team_id
    LEFT JOIN pit a  ON a.fixture_id  = o.fixture_id AND a.team_id  = o.away_team_id
    LEFT JOIN xg hx  ON hx.fixture_id = o.fixture_id AND hx.team_id = o.home_team_id
    LEFT JOIN xg ax  ON ax.fixture_id = o.fixture_id AND ax.team_id = o.away_team_id
    LEFT JOIN pace_team hp ON hp.fixture_id = o.fixture_id AND hp.team_id = o.home_team_id
    LEFT JOIN pace_team ap ON ap.fixture_id = o.fixture_id AND ap.team_id = o.away_team_id
    LEFT JOIN league_pace_median lpm ON lpm.fixture_id = o.fixture_id
    LEFT JOIN last5 hl ON hl.fixture_id = o.fixture_id AND hl.team_id = o.home_team_id
    LEFT JOIN last5 al ON al.fixture_id = o.fixture_id AND al.team_id = o.away_team_id
    LEFT JOIN line_move lm ON lm.fixture_id = o.fixture_id AND lm.line_value = o.line_value AND lm.outcome = o.outcome
),

-- Premissas (booleanos). Cada uma só pode ser TRUE no lado a que pertence (gated por outcome),
-- então a soma dos 13 pesos é <=56 (Over) ou <=52 (Under) por linha.
flags AS (
    SELECT
        m.*,
        -- Over (Σ56)
        (m.outcome = 'Over') AND COALESCE(m.gf_comb  >= m.line_value + 0.5, FALSE) AS ataque_combinado,
        (m.outcome = 'Over') AND COALESCE(m.ga_comb  >= m.line_value,       FALSE) AS defesas_vazaveis,
        (m.outcome = 'Over') AND COALESCE(m.xg_comb  >= CAST(m.line_value AS NUMERIC) + NUMERIC '0.3', FALSE) AS xg_combinado_alto,
        (m.outcome = 'Over') AND COALESCE(m.pace_both >= m.pace_median,     FALSE) AS ritmo_alto,
        (m.outcome = 'Over') AND COALESCE(m.home_cs_pct < 35 AND m.away_cs_pct < 35, FALSE) AS ambos_vazam,
        (m.outcome = 'Over') AND COALESCE(m.home_over_cnt >= 3 AND m.away_over_cnt >= 3, FALSE) AS historico_over,
        (m.outcome = 'Over') AND COALESCE(m.linha_caiu, FALSE)                     AS linha_subindo,
        -- Under (Σ52)
        (m.outcome = 'Under') AND COALESCE(m.ga_comb <= m.line_value - 0.3, FALSE) AS defesas_firmes,
        (m.outcome = 'Under') AND COALESCE(m.home_cs_pct >= 40 AND m.away_cs_pct >= 40, FALSE) AS clean_sheets_altos,
        (m.outcome = 'Under') AND COALESCE(m.xg_comb <= CAST(m.line_value AS NUMERIC) - NUMERIC '0.3', FALSE) AS xg_baixo_combinado,
        (m.outcome = 'Under') AND COALESCE(m.home_fts_pct >= 35 OR m.away_fts_pct >= 35, FALSE) AS ataques_fracos,
        (m.outcome = 'Under') AND COALESCE(m.home_under_cnt >= 3 AND m.away_under_cnt >= 3, FALSE) AS historico_under,
        (m.outcome = 'Under') AND COALESCE(m.linha_caiu, FALSE)                    AS linha_descendo,
        -- penalidade específica (independe do lado)
        (m.line_value <= 0.5 OR m.line_value >= 4.5)                               AS linha_extrema
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        LEAST(
            12 * CAST(f.ataque_combinado   AS INT64)
          + 10 * CAST(f.defesas_vazaveis   AS INT64)
          +  8 * CAST(f.xg_combinado_alto  AS INT64)
          +  8 * CAST(f.ritmo_alto         AS INT64)
          +  6 * CAST(f.ambos_vazam        AS INT64)
          +  6 * CAST(f.historico_over     AS INT64)
          +  6 * CAST(f.linha_subindo      AS INT64)
          + 12 * CAST(f.defesas_firmes     AS INT64)
          + 10 * CAST(f.clean_sheets_altos AS INT64)
          + 10 * CAST(f.xg_baixo_combinado AS INT64)
          +  8 * CAST(f.ataques_fracos     AS INT64)
          +  6 * CAST(f.historico_under    AS INT64)
          +  6 * CAST(f.linha_descendo     AS INT64)
        , 55) AS pts_premissas,
        10 * CAST(f.linha_extrema AS INT64) AS penalidades_ou_pts
    FROM flags f
),

-- Cegueira (#41, ADR 0003): premissas que se aplicavam a esta linha, não acenderam, e não
-- acenderam por FALTA DE INSUMO. Gerada do mapa futebol_insumos_premissa(), nunca escrita à
-- mão. Aqui a aplicabilidade é o lado: numa linha de Under as 7 premissas do Over não estão
-- cegas, estão fora de jogo.
cegueira AS (
    SELECT
        s.*,
        ARRAY(SELECT premissa FROM UNNEST([
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(ataque_combinado, FALSE)
           AND (gf_comb IS NULL), FALSE), 'ataque_combinado', NULL),
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(defesas_vazaveis, FALSE)
           AND (ga_comb IS NULL), FALSE), 'defesas_vazaveis', NULL),
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(xg_combinado_alto, FALSE)
           AND (xg_comb IS NULL), FALSE), 'xg_combinado_alto', NULL),
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(ritmo_alto, FALSE)
           AND (pace_both IS NULL OR pace_median IS NULL), FALSE), 'ritmo_alto', NULL),
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(ambos_vazam, FALSE)
           AND (home_cs_pct IS NULL OR away_cs_pct IS NULL), FALSE), 'ambos_vazam', NULL),
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(historico_over, FALSE)
           AND (home_over_cnt IS NULL OR away_over_cnt IS NULL), FALSE), 'historico_over', NULL),
        IF(COALESCE((outcome = 'Over')
           AND NOT COALESCE(linha_subindo, FALSE)
           AND (prob_t24h IS NULL OR prob_t15m IS NULL), FALSE), 'linha_subindo', NULL),
        IF(COALESCE((outcome = 'Under')
           AND NOT COALESCE(defesas_firmes, FALSE)
           AND (ga_comb IS NULL), FALSE), 'defesas_firmes', NULL),
        IF(COALESCE((outcome = 'Under')
           AND NOT COALESCE(clean_sheets_altos, FALSE)
           AND (home_cs_pct IS NULL OR away_cs_pct IS NULL), FALSE), 'clean_sheets_altos', NULL),
        IF(COALESCE((outcome = 'Under')
           AND NOT COALESCE(xg_baixo_combinado, FALSE)
           AND (xg_comb IS NULL), FALSE), 'xg_baixo_combinado', NULL),
        IF(COALESCE((outcome = 'Under')
           AND NOT COALESCE(ataques_fracos, FALSE)
           AND (home_fts_pct IS NULL OR away_fts_pct IS NULL), FALSE), 'ataques_fracos', NULL),
        IF(COALESCE((outcome = 'Under')
           AND NOT COALESCE(historico_under, FALSE)
           AND (home_under_cnt IS NULL OR away_under_cnt IS NULL), FALSE), 'historico_under', NULL),
        IF(COALESCE((outcome = 'Under')
           AND NOT COALESCE(linha_descendo, FALSE)
           AND (prob_t24h IS NULL OR prob_t15m IS NULL), FALSE), 'linha_descendo', NULL)
    ]) AS premissa WHERE premissa IS NOT NULL) AS premissas_cegas
    FROM scored s
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    line_value,
    -- flags (transparência/debug)
    ataque_combinado,
    defesas_vazaveis,
    xg_combinado_alto,
    ritmo_alto,
    ambos_vazam,
    historico_over,
    linha_subindo,
    defesas_firmes,
    clean_sheets_altos,
    xg_baixo_combinado,
    ataques_fracos,
    historico_under,
    linha_descendo,
    linha_extrema,
    -- agregados
    pts_premissas,
    penalidades_ou_pts,
    -- cegueira: a lista é o que torna o número auditável.
    premissas_cegas,
    ARRAY_LENGTH(premissas_cegas) AS premissas_sem_dado,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    -- Só o lado do outcome pode disparar, então os bullets do outro lado nunca aparecem.
    ARRAY(SELECT e FROM UNNEST([
        IF(ataque_combinado,
           FORMAT('os dois somam %.1f gols/jogo (casa+fora), acima da linha %.1f', gf_comb, line_value), NULL),
        IF(defesas_firmes,
           FORMAT('defesas firmes: cedem só %.1f gols/jogo somados, abaixo da linha %.1f', ga_comb, line_value), NULL),
        IF(defesas_vazaveis,
           FORMAT('defesas vazáveis: cedem %.1f gols/jogo somados', ga_comb), NULL),
        IF(clean_sheets_altos,
           FORMAT('os dois seguram o zero com frequência (clean sheet %.0f%% e %.0f%%)', home_cs_pct, away_cs_pct), NULL),
        IF(xg_combinado_alto,
           FORMAT('xG combinado de %.2f acima da linha', xg_comb), NULL),
        IF(xg_baixo_combinado,
           FORMAT('xG combinado baixo (%.2f), abaixo da linha', xg_comb), NULL),
        IF(ritmo_alto,
           FORMAT('ritmo de %.1f finalizações+escanteios/jogo, acima da mediana da liga (%.1f)', pace_both, pace_median), NULL),
        IF(ataques_fracos,
           'ataque que trava: ao menos um passa em branco com frequência (≥35% dos jogos)', NULL),
        IF(ambos_vazam, 'os dois sofrem gol com frequência (clean sheet < 35%)', NULL),
        IF(historico_over,
           FORMAT('%d e %d dos últimos 5 de cada bateram o Over %.1f', home_over_cnt, away_over_cnt, line_value), NULL),
        IF(historico_under,
           FORMAT('%d e %d dos últimos 5 de cada ficaram no Under %.1f', home_under_cnt, away_under_cnt, line_value), NULL),
        IF(linha_subindo, 'mercado baixou a odd do Over (dinheiro entrando no Over)', NULL),
        IF(linha_descendo, 'mercado baixou a odd do Under (dinheiro entrando no Under)', NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: penalidade específica do O/U.
    ARRAY(SELECT a FROM UNNEST([
        IF(linha_extrema,
           FORMAT('⚠ linha extrema (%.1f) — odd vira juice/longshot (−10)', line_value), NULL)
    ]) AS a WHERE a IS NOT NULL) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM cegueira