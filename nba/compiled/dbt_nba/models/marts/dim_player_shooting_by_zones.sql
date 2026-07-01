

WITH dim_player_shooting_by_zones AS (

    SELECT
       *
    FROM `smartbetting-dados`.`nba`.`stg_season_averages_shooting_by_zone`
)

SELECT
    *,
    CURRENT_TIMESTAMP() AS loaded_at
FROM dim_player_shooting_by_zones