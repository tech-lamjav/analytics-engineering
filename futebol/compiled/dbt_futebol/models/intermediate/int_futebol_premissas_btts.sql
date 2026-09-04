

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- 2 outcomes (Yes/No) por fixture, com o eixo do jogo (mandante/visitante).
outcomes AS (
    SELECT
        f.fixture_id, f.competition, f.competition_id, f.season, f.kickoff_utc,
        f.home_team_id, f.away_team_id,
        side AS outcome
    FROM fixtures f
    CROSS JOIN UNNEST(['Yes', 'No']) AS side
),

-- Correção da Task 0 (look-ahead): agregados POINT-IN-TIME por (fixture, time), só com jogos
-- anteriores ao kickoff. Substitui fact_team_season_stats, que tem 1 snapshot por season (em
-- 24/25 = temporada fechada, com o próprio jogo dentro das médias).
pit AS (
    SELECT
        fixture_id, team_id,
        goals_for_avg_home, goals_for_avg_away,
        clean_sheet_total, failed_to_score_total, played_total
    FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`
),

-- Histórico BTTS: ambos marcaram (ou não) nos últimos 5 jogos FINALIZADOS de cada time, na
-- MESMA competição, MESMA season e ANTERIORES ao jogo. 1 array de booleanos por (fixture-alvo,
-- time). O filtro de season evita sangrar jogos da temporada passada pela pausa de off-season
-- (consistente com os joins de tss, que já são season-scoped).
finished AS (
    SELECT competition_id, season, kickoff_utc, home_team_id, away_team_id,
           (score_fulltime_home > 0 AND score_fulltime_away > 0) AS btts_occurred
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE 
    status_short IN ('FT', 'AET', 'PEN')
      AND score_fulltime_home IS NOT NULL
      AND score_fulltime_away IS NOT NULL
),
team_fixtures_long AS (
    SELECT home_team_id AS team_id, competition_id, season, kickoff_utc, btts_occurred FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, season, kickoff_utc, btts_occurred FROM finished
),
fixture_teams AS (
    SELECT fixture_id, competition_id, season, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc, away_team_id FROM fixtures
),
last5 AS (
    SELECT
        ft.fixture_id, ft.team_id,
        ARRAY_AGG(h.btts_occurred ORDER BY h.kickoff_utc DESC LIMIT 5) AS last5_btts
    FROM fixture_teams ft
    JOIN team_fixtures_long h
        ON h.team_id        = ft.team_id
       AND h.kickoff_utc    < ft.kickoff_utc
    GROUP BY ft.fixture_id, ft.team_id
),

-- Métricas brutas derivadas (por outcome).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome,

        -- gols feitos médios por venue (mandante em casa, visitante fora)
        h.goals_for_avg_home AS home_gf,
        a.goals_for_avg_away AS away_gf,

        -- clean sheet% / failed-to-score% por time (SAFE_DIVIDE p/ played_total=0)
        SAFE_DIVIDE(h.clean_sheet_total,     h.played_total) * 100 AS home_cs_pct,
        SAFE_DIVIDE(a.clean_sheet_total,     a.played_total) * 100 AS away_cs_pct,
        SAFE_DIVIDE(h.failed_to_score_total, h.played_total) * 100 AS home_fts_pct,
        SAFE_DIVIDE(a.failed_to_score_total, a.played_total) * 100 AS away_fts_pct,

        -- histórico BTTS: quantos dos últimos 5 de cada tiveram (ou não) os dois marcando.
        -- O IF na frente é a classe (b) do mapa (#41): COUNT sobre array VAZIO devolve 0 sem
        -- nenhum NULL para detectar, e esse zero é indistinguível de "cinco jogos, em nenhum
        -- deles os dois marcaram". Sem histórico nenhum a contagem é desconhecida. O corte é em
        -- ZERO jogo, não em cinco: 1 a 4 jogos é medição real de amostra curta.
        IF(hl.last5_btts IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(hl.last5_btts) b WHERE b))     AS home_btts_cnt,
        IF(al.last5_btts IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(al.last5_btts) b WHERE b))     AS away_btts_cnt,
        IF(hl.last5_btts IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(hl.last5_btts) b WHERE NOT b)) AS home_no_btts_cnt,
        IF(al.last5_btts IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(al.last5_btts) b WHERE NOT b)) AS away_no_btts_cnt
    FROM outcomes o
    LEFT JOIN pit h    ON h.fixture_id = o.fixture_id AND h.team_id = o.home_team_id
    LEFT JOIN pit a    ON a.fixture_id = o.fixture_id AND a.team_id = o.away_team_id
    LEFT JOIN last5 hl ON hl.fixture_id = o.fixture_id AND hl.team_id = o.home_team_id
    LEFT JOIN last5 al ON al.fixture_id = o.fixture_id AND al.team_id = o.away_team_id
),

-- Premissas (booleanos). Cada uma só pode ser TRUE no lado a que pertence (gated por outcome),
-- então a soma dos 7 pesos é <=34 (Yes) ou <=28 (No) por fixture -> sem clamp.
flags AS (
    SELECT
        m.*,
        -- Sim (Σ34): os dois marcam e os dois sofrem -> ambos os ataques furam
        (m.outcome = 'Yes') AND COALESCE(m.home_fts_pct < 30 AND m.away_fts_pct < 30, FALSE) AS ambos_marcam,
        (m.outcome = 'Yes') AND COALESCE(m.home_gf >= 1.2 AND m.away_gf >= 1.2, FALSE)        AS ataque_dos_dois,
        (m.outcome = 'Yes') AND COALESCE(m.home_cs_pct < 35 AND m.away_cs_pct < 35, FALSE)    AS defesas_vazaveis,
        (m.outcome = 'Yes') AND COALESCE(m.home_btts_cnt >= 3 AND m.away_btts_cnt >= 3, FALSE) AS historico_btts,
        -- Não (espelho, Σ28): basta UM lado travar -> "de um dos times" => OR
        (m.outcome = 'No')  AND COALESCE(m.home_cs_pct >= 45 OR m.away_cs_pct >= 45, FALSE)   AS defesa_forte,
        (m.outcome = 'No')  AND COALESCE(m.home_fts_pct >= 35 OR m.away_fts_pct >= 35, FALSE) AS ataque_trava,
        (m.outcome = 'No')  AND COALESCE(m.home_no_btts_cnt >= 3 OR m.away_no_btts_cnt >= 3, FALSE) AS historico_seco
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        ( 12 * CAST(f.ambos_marcam     AS INT64)
        +  8 * CAST(f.ataque_dos_dois  AS INT64)
        +  8 * CAST(f.defesas_vazaveis AS INT64)
        +  6 * CAST(f.historico_btts   AS INT64)
        + 12 * CAST(f.defesa_forte     AS INT64)
        + 10 * CAST(f.ataque_trava     AS INT64)
        +  6 * CAST(f.historico_seco   AS INT64)
        ) AS pts_premissas,
        0 AS penalidades_btts_pts
    FROM flags f
),

-- Cegueira (#41, ADR 0003): premissas que se aplicavam a esta linha, não acenderam, e não
-- acenderam por FALTA DE INSUMO. Gerada do mapa futebol_insumos_premissa(), nunca escrita à
-- mão. Aqui a aplicabilidade é o lado: numa linha 'No' as 4 premissas do 'Yes' não estão
-- cegas, estão fora de jogo.
cegueira AS (
    SELECT
        s.*,
        ARRAY(SELECT premissa FROM UNNEST([
        IF(COALESCE((outcome = 'Yes')
           AND NOT COALESCE(ambos_marcam, FALSE)
           AND (home_fts_pct IS NULL OR away_fts_pct IS NULL), FALSE), 'ambos_marcam', NULL),
        IF(COALESCE((outcome = 'Yes')
           AND NOT COALESCE(ataque_dos_dois, FALSE)
           AND (home_gf IS NULL OR away_gf IS NULL), FALSE), 'ataque_dos_dois', NULL),
        IF(COALESCE((outcome = 'Yes')
           AND NOT COALESCE(defesas_vazaveis, FALSE)
           AND (home_cs_pct IS NULL OR away_cs_pct IS NULL), FALSE), 'defesas_vazaveis', NULL),
        IF(COALESCE((outcome = 'Yes')
           AND NOT COALESCE(historico_btts, FALSE)
           AND (home_btts_cnt IS NULL OR away_btts_cnt IS NULL), FALSE), 'historico_btts', NULL),
        IF(COALESCE((outcome = 'No')
           AND NOT COALESCE(defesa_forte, FALSE)
           AND (home_cs_pct IS NULL OR away_cs_pct IS NULL), FALSE), 'defesa_forte', NULL),
        IF(COALESCE((outcome = 'No')
           AND NOT COALESCE(ataque_trava, FALSE)
           AND (home_fts_pct IS NULL OR away_fts_pct IS NULL), FALSE), 'ataque_trava', NULL),
        IF(COALESCE((outcome = 'No')
           AND NOT COALESCE(historico_seco, FALSE)
           AND (home_no_btts_cnt IS NULL OR away_no_btts_cnt IS NULL), FALSE), 'historico_seco', NULL)
    ]) AS premissa WHERE premissa IS NOT NULL) AS premissas_cegas
    FROM scored s
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    -- flags (transparência/debug)
    ambos_marcam,
    ataque_dos_dois,
    defesas_vazaveis,
    historico_btts,
    defesa_forte,
    ataque_trava,
    historico_seco,
    -- agregados
    pts_premissas,
    penalidades_btts_pts,
    -- cegueira: a lista é o que torna o número auditável.
    premissas_cegas,
    ARRAY_LENGTH(premissas_cegas) AS premissas_sem_dado,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    -- Só o lado do outcome pode disparar, então os bullets do outro lado nunca aparecem.
    ARRAY(SELECT e FROM UNNEST([
        IF(ambos_marcam,
           FORMAT('os dois marcam quase sempre (passam em branco só %.0f%% e %.0f%% dos jogos)', home_fts_pct, away_fts_pct), NULL),
        IF(defesa_forte,
           FORMAT('defesa forte: ao menos um segura o zero com frequência (clean sheet %.0f%% e %.0f%%)', home_cs_pct, away_cs_pct), NULL),
        IF(ataque_trava,
           FORMAT('ataque que trava: ao menos um passa em branco com frequência (%.0f%% e %.0f%% dos jogos)', home_fts_pct, away_fts_pct), NULL),
        IF(ataque_dos_dois,
           FORMAT('os dois atacam bem (%.1f e %.1f gols/jogo no mando)', home_gf, away_gf), NULL),
        IF(defesas_vazaveis,
           FORMAT('defesas vazáveis: os dois sofrem gol com frequência (clean sheet %.0f%% e %.0f%%)', home_cs_pct, away_cs_pct), NULL),
        IF(historico_btts,
           FORMAT('%d e %d dos últimos 5 de cada tiveram os dois marcando', home_btts_cnt, away_btts_cnt), NULL),
        -- historico_seco é um OR: acende com UM lado só. Se o outro não tem histórico, a
        -- contagem dele chega NULL (#41) e um %d sobre NULL faria o FORMAT inteiro virar NULL
        -- — o bullet SUMIRIA de uma premissa que acendeu. Aconteceu em 32 linhas, e é por isso
        -- que o lado sem histórico é escrito por extenso em vez de virar um zero que não medimos.
        IF(historico_seco,
           FORMAT('%s e %s dos últimos 5 de cada SEM os dois marcando',
                  IFNULL(CAST(home_no_btts_cnt AS STRING), 'sem histórico'),
                  IFNULL(CAST(away_no_btts_cnt AS STRING), 'sem histórico')), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: BTTS não tem penalidade específica (só as globais de odds, anexadas no mart).
    CAST([] AS ARRAY<STRING>) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM cegueira