{{ config(
    description='Staging table for NBA team season averages (general/advanced) from Balldontlie API. Team-level offensive/defensive ratings per 100 possessions.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_general_advanced') }}
),

cleaned_data AS (
    SELECT
        CAST(team.id AS INT64) AS team_id,
        CAST(season AS INT64) AS season,
        season_type,
        CAST(stats.off_rating AS FLOAT64) AS team_offensive_rating,
        CAST(stats.def_rating AS FLOAT64) AS team_defensive_rating,
        COALESCE(
            SAFE_CAST(stats.net_rating AS FLOAT64),
            CAST(stats.off_rating AS FLOAT64) - CAST(stats.def_rating AS FLOAT64)
        ) AS team_net_rating,
        SAFE_CAST(stats.poss AS FLOAT64) AS team_possessions,
        SAFE_CAST(stats.pace AS FLOAT64) AS team_pace,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data
