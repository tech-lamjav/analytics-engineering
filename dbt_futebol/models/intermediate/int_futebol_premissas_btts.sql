{{ config(
    materialized='table',
    description='S4 do Motor de Score — premissas de contexto do mercado AMBOS MARCAM / BTTS (market_id 8). 2 linhas por fixture: Yes e No. Sim: dois ataques ativos e defesas vazáveis (4 premissas, Σ34). Não (espelho): uma defesa forte ou um ataque que trava (3 premissas, Σ28). Σ por lado < 55 -> sem clamp. Cada premissa é 1 booleano que soma seu peso ao PTS_PREMISSAS (espelha §12.4). Convenções herdadas do S2: clean sheet%/failed-to-score% sobre o TOTAL da temporada (SAFE_DIVIDE p/ played_total=0); gols feitos médios por VENUE (mandante em casa, visitante fora). historico_btts/seco = últimos 5 jogos FINALIZADOS de cada time na MESMA competição, anteriores ao jogo (>=3 de 5 ~ 60%). Sem penalidade específica (só as globais, aplicadas no mart). Degradação graciosa: dado ausente -> premissa FALSE. evidencias[]/avisos[] = bullets pro front. O gate/edge/Score são aplicados no mart fact_value_opportunities (BTTS via de-vig de CONSENSO, pois a Pinnacle não precifica BTTS — valor_fonte=consenso).'
) }}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
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

tss AS (
    SELECT
        team_id, season, competition_id,
        goals_for_avg_home, goals_for_avg_away,
        clean_sheet_total, failed_to_score_total, played_total
    FROM {{ ref('fact_team_season_stats') }}
),

-- Histórico BTTS: ambos marcaram (ou não) nos últimos 5 jogos FINALIZADOS de cada time, na
-- MESMA competição, MESMA season e ANTERIORES ao jogo. 1 array de booleanos por (fixture-alvo,
-- time). O filtro de season evita sangrar jogos da temporada passada pela pausa de off-season
-- (consistente com os joins de tss, que já são season-scoped).
finished AS (
    SELECT competition_id, season, kickoff_utc, home_team_id, away_team_id,
           (goals_home > 0 AND goals_away > 0) AS btts_occurred
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
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
       AND h.competition_id = ft.competition_id
       AND h.season         = ft.season
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

        -- histórico BTTS: quantos dos últimos 5 de cada tiveram (ou não) os dois marcando
        (SELECT COUNT(*) FROM UNNEST(hl.last5_btts) b WHERE b)     AS home_btts_cnt,
        (SELECT COUNT(*) FROM UNNEST(al.last5_btts) b WHERE b)     AS away_btts_cnt,
        (SELECT COUNT(*) FROM UNNEST(hl.last5_btts) b WHERE NOT b) AS home_no_btts_cnt,
        (SELECT COUNT(*) FROM UNNEST(al.last5_btts) b WHERE NOT b) AS away_no_btts_cnt
    FROM outcomes o
    LEFT JOIN tss h    ON h.team_id  = o.home_team_id AND h.season = o.season AND h.competition_id = o.competition_id
    LEFT JOIN tss a    ON a.team_id  = o.away_team_id AND a.season = o.season AND a.competition_id = o.competition_id
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
        (m.outcome = 'Yes') AND (m.home_btts_cnt >= 3 AND m.away_btts_cnt >= 3)               AS historico_btts,
        -- Não (espelho, Σ28): basta UM lado travar -> "de um dos times" => OR
        (m.outcome = 'No')  AND COALESCE(m.home_cs_pct >= 45 OR m.away_cs_pct >= 45, FALSE)   AS defesa_forte,
        (m.outcome = 'No')  AND COALESCE(m.home_fts_pct >= 35 OR m.away_fts_pct >= 35, FALSE) AS ataque_trava,
        (m.outcome = 'No')  AND (m.home_no_btts_cnt >= 3 OR m.away_no_btts_cnt >= 3)          AS historico_seco
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
        IF(historico_seco,
           FORMAT('%d e %d dos últimos 5 de cada SEM os dois marcando', home_no_btts_cnt, away_no_btts_cnt), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: BTTS não tem penalidade específica (só as globais de odds, anexadas no mart).
    CAST([] AS ARRAY<STRING>) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
