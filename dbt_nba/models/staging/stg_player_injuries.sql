{{ config(
    description='Staging table for NBA player injuries from NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_player_injuries') }}
),

cleaned_data AS (
    SELECT
        player.id AS player_id,
        player.team_id AS team_id,
        season,
        CAST(return_date AS DATE) AS return_date,
        description,
        status,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data
