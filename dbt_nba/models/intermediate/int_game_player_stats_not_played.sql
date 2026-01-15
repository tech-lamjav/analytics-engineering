{{ config(
    description='Intermediate model that gets the games where players did not play'
) }}

WITH

injury_games AS (
    SELECT DISTINCT
        player_id,
        team_id,
        game_id
    FROM {{ ref('stg_game_player_stats') }}
    WHERE minutes = 0
)

SELECT * FROM injury_games