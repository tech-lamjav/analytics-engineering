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
    FROM source_data
    -- Mantém status nulo: lesão sem rótulo não deve sumir do pipeline de triggers.
    -- (status <> 'Probable' sozinho descartaria NULL silenciosamente, pois NULL <> x => NULL.)
    WHERE status IS NULL OR status <> 'Probable'
)

SELECT * FROM cleaned_data
