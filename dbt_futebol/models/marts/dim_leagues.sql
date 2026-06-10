{{ config(
    materialized='table',
    description='Dimensão de ligas/temporadas. 1 linha por (league_id, season_year). Cobre Brasileirão (2024/2025/2026) e Copa do Mundo (2026).'
) }}

SELECT
    league_id,
    season_year,
    league_name,
    league_type,
    country_name,
    country_code,
    league_logo_url,
    country_flag_url,
    season_start,
    season_end,
    season_current,
    coverage,
    loaded_at        AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM {{ ref('stg_futebol_leagues') }}
