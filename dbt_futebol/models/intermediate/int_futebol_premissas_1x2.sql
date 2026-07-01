{{ config(
    materialized='table',
    description='S1 do Motor de Score — premissas de contexto do mercado RESULTADO (1X2). 3 linhas por fixture (outcome Home/Draw/Away). S = lado apostado, O = adversário. Cada premissa é um booleano que soma seu peso ao PTS_PREMISSAS (espelha §12.1 do épico MOTOR_SCORE_CONFIABILIDADE.md). Penalidades específicas: pick_empate (-10), desfalque_proprio (-15). Degradação graciosa: dado ausente -> premissa FALSE (Copa sem xG/injuries). evidencias[]/avisos[] = bullets legíveis pro front. O gate/edge/Score são aplicados no mart fact_value_opportunities.'
) }}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

-- 3 outcomes por fixture; resolve S (apostado) e O (adversário) por lado.
outcomes AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Home' AS outcome, home_team_id AS s_team_id, away_team_id AS o_team_id, TRUE AS s_is_home
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Away', away_team_id, home_team_id, FALSE
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Draw', CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS BOOL)
    FROM fixtures
),

tss AS (
    SELECT
        team_id, season, competition_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        wins_home, draws_home, played_home,
        wins_away, draws_away, played_away
    FROM {{ ref('fact_team_season_stats') }}
),

-- 1 linha por (liga, season, time): snapshot mais recente; na Copa evita a linha duplicada
-- "Ranking of third-placed teams" preferindo o grupo principal.
standings_latest AS (
    SELECT league_id, season, team_id, rank, points, played_total, form
    FROM {{ ref('fact_standings_snapshot') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY snapshot_date DESC,
                 CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END
    ) = 1
),

-- Spine (fixture-alvo, time) p/ ancorar o xG ao kickoff do jogo (point-in-time).
fixture_team_spine AS (
    SELECT fixture_id, season, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, season, competition_id, kickoff_utc, away_team_id FROM fixtures
),
-- xG médio do time ATÉ o jogo: mesma season/competição e jogos ANTERIORES ao kickoff (date_utc <
-- DATE(kickoff)) — time-bounded igual ao h2h/last5, sem look-ahead em fixtures já jogadas. P/ jogos
-- FUTUROS == média da season (todos os jogos com stats são anteriores). Brasileirão preenchido;
-- Copa ~vazio -> NULL -> premissa de xG não dispara.
xg AS (
    SELECT
        sp.fixture_id, sp.team_id,
        AVG(st.expected_goals)  AS xg_for_avg,
        AVG(opp.expected_goals) AS xg_against_avg
    FROM fixture_team_spine sp
    JOIN {{ ref('fact_fixture_stats') }} st
        ON  st.team_id        = sp.team_id
        AND st.season         = sp.season
        AND st.competition_id = sp.competition_id
        AND st.date_utc       < DATE(sp.kickoff_utc)
    JOIN {{ ref('fact_fixture_stats') }} opp
        ON  opp.fixture_id = st.fixture_id
        AND opp.team_id   != st.team_id
    GROUP BY sp.fixture_id, sp.team_id
),

-- ============================================================================
-- S7: desfalque PESADO POR IMPORTÂNCIA. Conta só TITULAR IMPORTANTE fora
-- ('Missing Fixture' AND is_important) por (fixture, time). Fonte:
-- int_futebol_desfalques (injuries x proxy de importância de fact_fixture_player_stats).
-- 'Questionable' (dúvida) NÃO dispara — conservador, fiel à §12.1 ("desfalque de
-- titular"); o tipo segue guardado/exibido em int_futebol_desfalques (front).
-- ============================================================================
desf AS (
    SELECT
        fixture_id,
        team_id,
        COUNTIF(injury_type = 'Missing Fixture' AND is_important) AS missing_important_count
    FROM {{ ref('int_futebol_desfalques') }}
    GROUP BY fixture_id, team_id
),

-- H2H: confrontos diretos ANTERIORES ao jogo; conta vitórias de S (só Home/Away).
h2h AS (
    SELECT
        o.fixture_id, o.outcome,
        COUNT(*) AS h2h_total,
        COUNTIF(
            (h.home_team_id = o.s_team_id AND h.home_team_winner)
         OR (h.away_team_id = o.s_team_id AND h.away_team_winner)
        ) AS s_wins
    FROM outcomes o
    JOIN {{ ref('fact_h2h') }} h
        ON h.h2h_pair_key = CONCAT(
               CAST(LEAST(o.s_team_id, o.o_team_id) AS STRING), '-',
               CAST(GREATEST(o.s_team_id, o.o_team_id) AS STRING))
       AND h.fixture_id  != o.fixture_id
       AND h.kickoff_utc  < o.kickoff_utc
    WHERE o.s_team_id IS NOT NULL
    GROUP BY o.fixture_id, o.outcome
),

-- Métricas brutas derivadas (por outcome).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.s_is_home,

        -- ataque de S no seu campo / defesa de O no campo dele (forca_mismatch)
        IF(o.s_is_home, s.goals_for_avg_home, s.goals_for_avg_away)          AS s_gf_venue,
        IF(o.s_is_home, od.goals_against_avg_away, od.goals_against_avg_home) AS o_ga_venue,

        -- aproveitamento (mando)
        (s.wins_home * 3 + s.draws_home) / NULLIF(s.played_home * 3, 0) * 100 AS pct_pts_home,
        (s.wins_away * 3 + s.draws_away) / NULLIF(s.played_away * 3, 0) * 100 AS aprov_fora,

        -- xG (superioridade_xg)
        sx.xg_for_avg      AS s_xg_for,
        ox.xg_against_avg  AS o_xg_against,

        -- desfalques pesados por importância (S7): só titular importante fora conta
        COALESCE(si.missing_important_count, 0) AS s_missing,
        COALESCE(oi.missing_important_count, 0) AS o_missing,

        -- tabela (superioridade_tabela)
        ss.rank                                   AS s_rank,
        os.rank                                   AS o_rank,
        ss.points / NULLIF(ss.played_total, 0)    AS s_ppg,
        os.points / NULLIF(os.played_total, 0)    AS o_ppg,

        -- forma: vitórias nos últimos 5 (conta 'W' nos últimos 5 chars do form de S)
        ( LENGTH(RIGHT(COALESCE(ss.form, ''), 5))
        - LENGTH(REPLACE(RIGHT(COALESCE(ss.form, ''), 5), 'W', '')) ) AS n_wins_last5,

        -- h2h
        COALESCE(hh.h2h_total, 0) AS h2h_total,
        COALESCE(hh.s_wins, 0)    AS s_wins
    FROM outcomes o
    LEFT JOIN tss s   ON s.team_id  = o.s_team_id AND s.season  = o.season AND s.competition_id  = o.competition_id
    LEFT JOIN tss od  ON od.team_id = o.o_team_id AND od.season = o.season AND od.competition_id = o.competition_id
    LEFT JOIN standings_latest ss ON ss.team_id = o.s_team_id AND ss.season = o.season AND ss.league_id = o.competition_id
    LEFT JOIN standings_latest os ON os.team_id = o.o_team_id AND os.season = o.season AND os.league_id = o.competition_id
    LEFT JOIN xg sx   ON sx.fixture_id = o.fixture_id AND sx.team_id = o.s_team_id
    LEFT JOIN xg ox   ON ox.fixture_id = o.fixture_id AND ox.team_id = o.o_team_id
    LEFT JOIN desf si  ON si.fixture_id = o.fixture_id AND si.team_id = o.s_team_id
    LEFT JOIN desf oi  ON oi.fixture_id = o.fixture_id AND oi.team_id = o.o_team_id
    LEFT JOIN h2h hh  ON hh.fixture_id = o.fixture_id AND hh.outcome = o.outcome
),

-- Premissas (booleanos) e pesos.
flags AS (
    SELECT
        m.*,
        COALESCE(m.s_gf_venue >= 1.4 AND m.o_ga_venue >= 1.3, FALSE)        AS forca_mismatch,
        COALESCE(m.s_xg_for - m.o_xg_against >= 0.3, FALSE)                 AS superioridade_xg,
        CASE
            WHEN m.s_is_home       AND m.pct_pts_home >= 55 THEN 8
            WHEN m.s_is_home = FALSE AND m.aprov_fora  >= 45 THEN 4
            ELSE 0
        END                                                                AS pts_mando,
        COALESCE(m.o_missing >= 1 AND m.s_missing = 0, FALSE)              AS desfalque_adversario,
        (COALESCE(m.o_rank - m.s_rank >= 6, FALSE)
            OR COALESCE(m.s_ppg >= 1.3 * m.o_ppg, FALSE))                  AS superioridade_tabela,
        COALESCE(m.n_wins_last5 >= 3, FALSE)                               AS forma,
        COALESCE(m.h2h_total >= 1 AND m.s_wins * 2 >= m.h2h_total, FALSE)  AS h2h_favoravel,
        -- penalidades específicas 1X2
        (m.outcome = 'Draw')                                              AS pick_empate,
        (m.s_missing >= 1)                                                AS desfalque_proprio
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        (f.pts_mando > 0) AS mando,
        (
            12 * CAST(f.forca_mismatch       AS INT64)
          +  8 * CAST(f.superioridade_xg     AS INT64)
          +       f.pts_mando
          +  8 * CAST(f.desfalque_adversario AS INT64)
          +  6 * CAST(f.superioridade_tabela AS INT64)
          +  5 * CAST(f.forma                AS INT64)
          +  4 * CAST(f.h2h_favoravel        AS INT64)
        ) AS pts_premissas,
        (
            10 * CAST(f.pick_empate       AS INT64)
          + 15 * CAST(f.desfalque_proprio AS INT64)
        ) AS penalidades_1x2_pts
    FROM flags f
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    -- flags (transparência/debug)
    forca_mismatch,
    superioridade_xg,
    mando,
    pts_mando,
    desfalque_adversario,
    superioridade_tabela,
    forma,
    h2h_favoravel,
    pick_empate,
    desfalque_proprio,
    s_missing,
    -- agregados
    pts_premissas,
    penalidades_1x2_pts,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(forca_mismatch,
           FORMAT('marca %.1f gol/jogo %s e o adversário cede %.1f %s',
                  s_gf_venue, IF(s_is_home, 'em casa', 'fora'),
                  o_ga_venue, IF(s_is_home, 'fora', 'em casa')), NULL),
        IF(superioridade_xg,
           FORMAT('cria %.2f xG/jogo contra %.2f que o adversário costuma ceder',
                  s_xg_for, o_xg_against), NULL),
        IF(mando,
           IF(s_is_home,
              FORMAT('%.0f%% dos pontos como mandante', pct_pts_home),
              FORMAT('%.0f%% de aproveitamento como visitante', aprov_fora)), NULL),
        IF(desfalque_adversario,
           FORMAT('adversário com %d titular(es) importante(s) fora e time completo', o_missing), NULL),
        IF(superioridade_tabela, 'claramente superior na tabela', NULL),
        IF(forma, FORMAT('%d vitórias nos últimos 5 jogos', n_wins_last5), NULL),
        IF(h2h_favoravel,
           FORMAT('venceu %d dos últimos %d confrontos diretos', s_wins, h2h_total), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: penalidades específicas do 1X2.
    ARRAY(SELECT a FROM UNNEST([
        IF(pick_empate, '⚠ empate é a saída mais difícil de prever (−10)', NULL),
        IF(desfalque_proprio,
           FORMAT('⚠ desfalcado: %d titular(es) importante(s) fora (−15)', s_missing), NULL)
    ]) AS a WHERE a IS NOT NULL) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
