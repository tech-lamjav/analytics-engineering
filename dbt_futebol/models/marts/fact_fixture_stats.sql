{{ config(
    materialized='table',
    partition_by={'field': 'date_utc', 'data_type': 'date'},
    cluster_by=['fixture_id', 'team_id'],
    description='Estatística agregada por time por jogo (/fixtures/statistics). 2 linhas por fixture_id (mandante e visitante) — base direta do modelo Poisson e do value betting. Particionada por DATE(date_utc) (data do jogo, vinda de fact_fixtures) e clusterizada por (fixture_id, team_id). expected_goals (xG) e goals_prevented vêm da própria API-Football. Reconstruída full a cada run.'
) }}

WITH stats AS (
    SELECT * FROM {{ ref('stg_futebol_fixture_statistics') }}
),

fixtures AS (
    SELECT
        fixture_id,
        competition,
        competition_id,
        season,
        date_utc,
        home_team_id,
        away_team_id
    FROM {{ ref('fact_fixtures') }}
)

SELECT
    s.fixture_id,
    f.competition,
    f.competition_id,
    f.season,
    f.date_utc,

    s.team_id,
    s.team_name,
    CASE
        WHEN s.team_id = f.home_team_id THEN 'home'
        WHEN s.team_id = f.away_team_id THEN 'away'
    END                                          AS team_side,

    -- estatística de jogo (do pivot em stg)
    s.shots_on_goal,
    s.shots_off_goal,
    s.total_shots,
    s.blocked_shots,
    s.shots_insidebox,
    s.shots_outsidebox,
    s.fouls,
    s.corner_kicks,
    s.offsides,
    s.ball_possession,
    s.yellow_cards,
    s.red_cards,
    s.goalkeeper_saves,
    s.total_passes,
    s.passes_accurate,
    s.passes_pct,

    -- xG e goals_prevented vêm da própria API-Football (/fixtures/statistics)
    s.expected_goals,
    s.goals_prevented,

    s.loaded_at         AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM stats s
INNER JOIN fixtures f ON s.fixture_id = f.fixture_id
-- Defensivo: 1 arquivo por fixture já garante 2 linhas (mandante/visitante).
-- Mantém o idioma de dedup de fact_fixtures/dim_*.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY s.fixture_id, s.team_id
    ORDER BY s.loaded_at DESC
) = 1
