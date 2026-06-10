{{ config(
    materialized='table',
    description='Dimensão de times. 1 linha por team_id (dedup por loaded_at mais recente). Inclui clubes do Brasileirão (national=FALSE) e seleções da Copa do Mundo (national=TRUE).'
) }}

SELECT
    team_id,
    team_name,
    team_code,
    team_country,
    team_founded_year,
    national,
    team_logo_url,
    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM {{ ref('stg_futebol_teams') }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY team_id
    ORDER BY loaded_at DESC, requested_season DESC
) = 1
