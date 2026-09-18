

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
FROM `smartbetting-dados`.`futebol`.`stg_futebol_teams`
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY team_id
    ORDER BY loaded_at DESC, requested_season DESC
) = 1