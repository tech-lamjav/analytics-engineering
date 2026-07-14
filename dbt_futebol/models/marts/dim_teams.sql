{{ config(
    materialized='table',
    description='Dimensão de times. 1 linha por team_id (dedup por loaded_at mais recente, cross-liga: um clube presente em várias competições — ex.: Flamengo em Brasileirão/Copa do Brasil/Libertadores — colapsa em 1 linha). Inclui clubes brasileiros (Série A/B, Copa do Brasil), clubes sul-americanos (Libertadores/Sudamericana) e seleções da Copa do Mundo (national=TRUE).'
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
