{{ config(
    description='Staging table for NBA active players from NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_active_players') }}
),

cleaned_data AS (
    SELECT
        id AS player_id,
        team.id AS team_id,
        team.full_name AS team_name,
        team.abbreviation AS team_abbreviation,
        TRIM(first_name || ' ' || last_name) AS player_name,
        CONCAT(TRIM(last_name || ', ' || first_name), ' (', team.abbreviation, ')') AS last_name_first_team,
        TRIM(position) AS position,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data