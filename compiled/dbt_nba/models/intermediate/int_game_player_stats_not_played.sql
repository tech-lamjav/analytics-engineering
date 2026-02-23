

WITH

injury_games AS (
    SELECT DISTINCT
        player_id,
        team_id,
        game_id
    FROM `smartbetting-dados`.`nba`.`stg_game_player_stats`
    WHERE minutes = 0
)

SELECT * FROM injury_games