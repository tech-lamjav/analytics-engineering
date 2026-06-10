{{ config(
    materialized='table',
    partition_by={'field': 'date_utc', 'data_type': 'date'},
    cluster_by=['fixture_id', 'team_id', 'player_id'],
    description='Estatística por jogador por jogo (/fixtures/players). ~22-30 linhas por fixture_id (titulares + entrantes, ambos os times) — base para props de jogador e forma individual ponderada de time. Particionada por DATE(date_utc) (data do jogo, de fact_fixtures) e clusterizada por (fixture_id, team_id, player_id). position/minutes vêm do próprio jogo. Latest-wins por (fixture_id, player_id). Reconstruída full a cada run.'
) }}

WITH player_stats AS (
    SELECT * FROM {{ ref('stg_futebol_fixture_player_stats') }}
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
    ps.fixture_id,
    f.competition,
    f.competition_id,
    f.season,
    f.date_utc,

    ps.team_id,
    ps.team_name,
    CASE
        WHEN ps.team_id = f.home_team_id THEN 'home'
        WHEN ps.team_id = f.away_team_id THEN 'away'
    END                                          AS team_side,

    ps.player_id,
    ps.player_name,
    ps.position,
    ps.shirt_number,
    ps.minutes,
    ps.rating,
    ps.is_captain,
    ps.is_substitute,

    -- finalização / gols
    ps.shots_total,
    ps.shots_on,
    ps.goals_total,
    ps.goals_conceded,
    ps.assists,
    ps.saves,
    ps.offsides,

    -- passes
    ps.passes_total,
    ps.passes_key,
    ps.passes_accuracy,

    -- defesa / duelos / dribles
    ps.tackles_total,
    ps.tackles_blocks,
    ps.interceptions,
    ps.duels_total,
    ps.duels_won,
    ps.dribbles_attempts,
    ps.dribbles_success,
    ps.dribbles_past,

    -- disciplina
    ps.fouls_drawn,
    ps.fouls_committed,
    ps.yellow_cards,
    ps.red_cards,

    -- pênaltis
    ps.penalty_won,
    ps.penalty_committed,
    ps.penalty_scored,
    ps.penalty_missed,
    ps.penalty_saved,

    ps.loaded_at        AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM player_stats ps
INNER JOIN fixtures f ON ps.fixture_id = f.fixture_id
-- Defensivo: 1 arquivo por fixture já garante 1 linha por jogador.
-- Mantém o idioma de dedup de fact_fixture_stats/fact_fixtures.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ps.fixture_id, ps.player_id
    ORDER BY ps.loaded_at DESC
) = 1
