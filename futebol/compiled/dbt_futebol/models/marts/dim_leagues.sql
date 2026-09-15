

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
FROM `smartbetting-dados`.`futebol`.`stg_futebol_leagues`
-- Defensivo (idioma das dims irmãs dim_teams/dim_players): latest-wins por
-- (league_id, season_year). Hoje o feed _current.json sobrescreve in-place (1 linha/chave),
-- mas se algum dia virar date-stampado/acumulativo (como aconteceu com standings) o QUALIFY
-- auto-corrige em vez de só quebrar no teste de unicidade.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY league_id, season_year
    ORDER BY loaded_at DESC
) = 1