{{ config(
    description='Staging table for NBA season averages (general/advanced) from NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_season_averages_general_advanced') }}
),

cleaned_data AS (
    SELECT
        -- Player information
        player.id AS player_id,

        --CAST(stats.poss AS INTEGER) AS possessions,
        CAST(stats.off_rating AS FLOAT64) AS offensive_rating,
        CAST(stats.def_rating AS FLOAT64) AS defensive_rating,

        --CAST(stats.poss AS INTEGER) * CAST(stats.off_rating AS FLOAT64) AS offensive_rating_points,
        --CAST(stats.poss AS INTEGER) * CAST(stats.def_rating AS FLOAT64) AS defensive_rating_points,

        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data