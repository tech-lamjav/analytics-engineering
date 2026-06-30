{{ config(
    materialized='table',
    description='S5 do Motor de Score — premissas de contexto do mercado DUPLA CHANCE (market_id 12). 2 linhas por fixture: 1X (mandante ou empate, S=Home) e X2 (empate ou visitante, S=Away). DC é aposta de proteção: vale quando o mercado superprecifica a zebra do lado DESCOBERTO (O). 4 premissas (Σ34, sem clamp — bem abaixo de 55), espelha §12.5. lado_coberto_forte REUSA forca_mismatch/superioridade_tabela do int_futebol_premissas_1x2 (do lado S); adversario_limitado reusa o h2h_favoravel do 1X2. equilibrio_defensivo e invicto_recente derivam de fact_team_season_stats (gols sofridos no total) e dos jogos FINALIZADOS da MESMA season/competição anteriores ao jogo (goleados = cedeu 3+, e derrotas nos últimos 5) — o filtro de season evita sangrar a temporada passada pela pausa de off-season. O 12 (sem empate) NÃO é produzido (não casa com o padrão S/O da §12.5). Penalidade específica (odd_muito_baixa <1,20) e o gate próprio (melhor_odd >=1,25, sem odd_juice) são aplicados no mart fact_value_opportunities. Degradação graciosa: dado ausente -> premissa FALSE. evidencias[]/avisos[] = bullets pro front.'
) }}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

-- 2 outcomes: 1X (S=Home, O=Away) e X2 (S=Away, O=Home). s_1x2_outcome casa o lado S no 1X2.
outcomes AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           '1X' AS outcome, home_team_id AS s_team_id, away_team_id AS o_team_id,
           'Home' AS s_1x2_outcome
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'X2', away_team_id, home_team_id, 'Away'
    FROM fixtures
),

-- Reuso das premissas do 1X2 (do lado S): forca_mismatch + superioridade_tabela (lado_coberto_forte)
-- e h2h_favoravel (adversario_limitado). Garante consistência com o ramo 1X2.
reuse_1x2 AS (
    SELECT fixture_id, outcome AS x1_outcome,
           forca_mismatch, superioridade_tabela, h2h_favoravel
    FROM {{ ref('int_futebol_premissas_1x2') }}
),

tss AS (
    SELECT
        team_id, season, competition_id,
        goals_against_avg_total,
        wins_total, draws_total, played_total
    FROM {{ ref('fact_team_season_stats') }}
),

-- Jogos finalizados (mesma competição, MESMA season, anteriores) -> goleados (cedeu 3+) e
-- resultado por time. O filtro de season (aplicado no team_hist) evita sangrar jogos da
-- temporada passada pela pausa de off-season (consistente com tss/1X2/O/U/BTTS, season-scoped).
finished AS (
    SELECT competition_id, season, kickoff_utc, home_team_id, away_team_id, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),
team_results_long AS (
    SELECT home_team_id AS team_id, competition_id, season, kickoff_utc,
           goals_away AS conceded, (goals_away > goals_home) AS lost FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, season, kickoff_utc,
           goals_home, (goals_home > goals_away) FROM finished
),
team_fixtures AS (
    SELECT fixture_id, competition_id, season, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc, away_team_id FROM fixtures
),
-- % de jogos cedendo 3+ (equilibrio_defensivo) e o array de derrotas dos últimos 5 (invicto_recente).
team_hist AS (
    SELECT
        tf.fixture_id, tf.team_id,
        SAFE_DIVIDE(COUNTIF(h.conceded >= 3), COUNT(*))              AS thrash_rate,
        ARRAY_AGG(h.lost ORDER BY h.kickoff_utc DESC LIMIT 5)        AS last5_lost
    FROM team_fixtures tf
    JOIN team_results_long h
        ON h.team_id        = tf.team_id
       AND h.competition_id = tf.competition_id
       AND h.season         = tf.season
       AND h.kickoff_utc    < tf.kickoff_utc
    GROUP BY tf.fixture_id, tf.team_id
),

-- Métricas brutas derivadas (por outcome).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome,

        -- gols sofridos no total dos dois (equilibrio_defensivo)
        s.goals_against_avg_total  AS s_ga_total,
        od.goals_against_avg_total AS o_ga_total,
        -- % de jogos goleados dos dois
        st.thrash_rate             AS s_thrash_rate,
        ot.thrash_rate             AS o_thrash_rate,

        -- aproveitamento do adversário descoberto O (total)
        (od.wins_total * 3 + od.draws_total) / NULLIF(od.played_total * 3, 0) * 100 AS o_aproveitamento,

        -- invicto de S nos últimos 5 (derrotas e nº de jogos com histórico). Lê last5_lost do
        -- próprio st (team_hist já traz thrash_rate E last5_lost por (fixture,time)) — sem self-join extra.
        (SELECT COUNT(*) FROM UNNEST(st.last5_lost) l WHERE l) AS s_losses_last5,
        ARRAY_LENGTH(st.last5_lost)                            AS s_games_last5,

        -- reuso 1X2 (lado S)
        COALESCE(x.forca_mismatch, FALSE)       AS x_forca_mismatch,
        COALESCE(x.superioridade_tabela, FALSE) AS x_superioridade_tabela,
        COALESCE(x.h2h_favoravel, FALSE)        AS x_h2h_favoravel
    FROM outcomes o
    LEFT JOIN tss s        ON s.team_id  = o.s_team_id AND s.season  = o.season AND s.competition_id  = o.competition_id
    LEFT JOIN tss od       ON od.team_id = o.o_team_id AND od.season = o.season AND od.competition_id = o.competition_id
    LEFT JOIN team_hist st ON st.fixture_id = o.fixture_id AND st.team_id = o.s_team_id
    LEFT JOIN team_hist ot ON ot.fixture_id = o.fixture_id AND ot.team_id = o.o_team_id
    LEFT JOIN reuse_1x2 x  ON x.fixture_id  = o.fixture_id AND x.x1_outcome = o.s_1x2_outcome
),

-- Premissas (booleanos) e pesos.
flags AS (
    SELECT
        m.*,
        -- lado coberto forte: reusa forca_mismatch/superioridade_tabela do 1X2 (lado S)
        (m.x_forca_mismatch OR m.x_superioridade_tabela)                          AS lado_coberto_forte,
        -- equilíbrio defensivo: os dois cedem pouco e quase não são goleados
        ( COALESCE(m.s_ga_total <= 1.3 AND m.o_ga_total <= 1.3, FALSE)
          AND COALESCE(m.s_thrash_rate < 0.30 AND m.o_thrash_rate < 0.30, FALSE) ) AS equilibrio_defensivo,
        -- adversário limitado: O com baixo aproveitamento OU retrospecto ruim vs S (h2h)
        ( COALESCE(m.o_aproveitamento < 45, FALSE) OR m.x_h2h_favoravel )          AS adversario_limitado,
        -- invicto recente: S sem derrota nos últimos 5 (exige >=3 jogos p/ não disparar sem dado)
        ( COALESCE(m.s_games_last5 >= 3, FALSE) AND COALESCE(m.s_losses_last5 = 0, FALSE) ) AS invicto_recente
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        ( 12 * CAST(f.lado_coberto_forte   AS INT64)
        +  8 * CAST(f.equilibrio_defensivo AS INT64)
        +  8 * CAST(f.adversario_limitado  AS INT64)
        +  6 * CAST(f.invicto_recente      AS INT64)
        ) AS pts_premissas,
        0 AS penalidades_dc_pts
    FROM flags f
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    -- flags (transparência/debug)
    lado_coberto_forte,
    equilibrio_defensivo,
    adversario_limitado,
    invicto_recente,
    -- agregados
    pts_premissas,
    penalidades_dc_pts,

    -- "por quê": premissas que dispararam, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(lado_coberto_forte,
           'o lado coberto (favorito + empate) é o mais forte do confronto', NULL),
        IF(equilibrio_defensivo,
           FORMAT('defesas equilibradas: os dois cedem pouco (%.1f e %.1f gols/jogo) e quase não são goleados',
                  s_ga_total, o_ga_total), NULL),
        IF(adversario_limitado,
           'adversário descoberto é limitado (aproveitamento baixo ou retrospecto ruim no confronto)', NULL),
        IF(invicto_recente,
           FORMAT('sem derrota nos últimos %d jogos', s_games_last5), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: a penalidade específica (odd_muito_baixa) é odds-based, anexada no mart.
    CAST([] AS ARRAY<STRING>) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
