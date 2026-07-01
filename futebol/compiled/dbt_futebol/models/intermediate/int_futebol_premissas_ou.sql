

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

tss AS (
    SELECT
        team_id, season, competition_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        clean_sheet_total, failed_to_score_total, played_total
    FROM `smartbetting-dados`.`futebol`.`fact_team_season_stats`
),

-- xG médio de ATAQUE por time-season (sem self-join: O/U só precisa do xG_for de cada um;
-- Brasileirão preenchido, Copa ~vazio -> NULL -> premissa de xG não dispara).
xg AS (
    SELECT team_id, season, competition_id, AVG(expected_goals) AS xg_for_avg
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats`
    GROUP BY team_id, season, competition_id
),

-- Ritmo: finalizações+escanteios por time-jogo -> média por time-season; mediana da liga
-- sobre as MÉDIAS por time (grão coerente com a comparação das duas médias). Brasileirão only.
pace_team AS (
    SELECT team_id, season, competition_id,
           AVG(total_shots + corner_kicks) AS pace_avg
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats`
    GROUP BY team_id, season, competition_id
),
league_pace_median AS (
    SELECT competition_id, season,
           APPROX_QUANTILES(pace_avg, 2)[OFFSET(1)] AS pace_median
    FROM pace_team
    GROUP BY competition_id, season
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
        AVG(IF(collection_window = 't24h', 1.0 / odd_decimal, NULL)) AS prob_t24h,
        AVG(IF(collection_window = 't15m', 1.0 / odd_decimal, NULL)) AS prob_t15m
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

        -- histórico Over/Under: quantos dos últimos 5 de cada bateram a linha
        (SELECT COUNT(*) FROM UNNEST(hl.last5_totals) g WHERE g > o.line_value) AS home_over_cnt,
        (SELECT COUNT(*) FROM UNNEST(al.last5_totals) g WHERE g > o.line_value) AS away_over_cnt,
        (SELECT COUNT(*) FROM UNNEST(hl.last5_totals) g WHERE g < o.line_value) AS home_under_cnt,
        (SELECT COUNT(*) FROM UNNEST(al.last5_totals) g WHERE g < o.line_value) AS away_under_cnt,

        -- movimento de consenso do lado deste outcome (Over ou Under): "linha caiu" = prob
        -- implícita média SUBIU (t15m > t24h) = odd caiu (dinheiro entrando neste lado)
        COALESCE(lm.prob_t15m > lm.prob_t24h, FALSE)         AS linha_caiu
    FROM outcomes o
    LEFT JOIN tss h  ON h.team_id  = o.home_team_id AND h.season  = o.season AND h.competition_id  = o.competition_id
    LEFT JOIN tss a  ON a.team_id  = o.away_team_id AND a.season  = o.season AND a.competition_id  = o.competition_id
    LEFT JOIN xg hx  ON hx.team_id = o.home_team_id AND hx.season = o.season AND hx.competition_id = o.competition_id
    LEFT JOIN xg ax  ON ax.team_id = o.away_team_id AND ax.season = o.season AND ax.competition_id = o.competition_id
    LEFT JOIN pace_team hp ON hp.team_id = o.home_team_id AND hp.season = o.season AND hp.competition_id = o.competition_id
    LEFT JOIN pace_team ap ON ap.team_id = o.away_team_id AND ap.season = o.season AND ap.competition_id = o.competition_id
    LEFT JOIN league_pace_median lpm ON lpm.competition_id = o.competition_id AND lpm.season = o.season
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
        (m.outcome = 'Over') AND COALESCE(m.xg_comb  >= m.line_value + 0.3, FALSE) AS xg_combinado_alto,
        (m.outcome = 'Over') AND COALESCE(m.pace_both >= m.pace_median,     FALSE) AS ritmo_alto,
        (m.outcome = 'Over') AND COALESCE(m.home_cs_pct < 35 AND m.away_cs_pct < 35, FALSE) AS ambos_vazam,
        (m.outcome = 'Over') AND (m.home_over_cnt >= 3 AND m.away_over_cnt >= 3)   AS historico_over,
        (m.outcome = 'Over') AND m.linha_caiu                                      AS linha_subindo,
        -- Under (Σ52)
        (m.outcome = 'Under') AND COALESCE(m.ga_comb <= m.line_value - 0.3, FALSE) AS defesas_firmes,
        (m.outcome = 'Under') AND COALESCE(m.home_cs_pct >= 40 AND m.away_cs_pct >= 40, FALSE) AS clean_sheets_altos,
        (m.outcome = 'Under') AND COALESCE(m.xg_comb <= m.line_value - 0.3, FALSE) AS xg_baixo_combinado,
        (m.outcome = 'Under') AND COALESCE(m.home_fts_pct >= 35 OR m.away_fts_pct >= 35, FALSE) AS ataques_fracos,
        (m.outcome = 'Under') AND (m.home_under_cnt >= 3 AND m.away_under_cnt >= 3) AS historico_under,
        (m.outcome = 'Under') AND m.linha_caiu                                     AS linha_descendo,
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
FROM scored