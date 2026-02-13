

WITH source_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`raw_season_averages_general_base`
),

cleaned_data AS (
    SELECT
        -- Player information
        player.id AS player_id,

        -- Basic statistics
        --CAST(stats.gp AS INTEGER) AS games_played,
        --CAST(stats.min AS FLOAT64) AS minutes,
        CAST(stats.pts AS FLOAT64) AS points,
        CAST(stats.reb AS FLOAT64) AS rebounds,
        CAST(stats.pts AS FLOAT64) + CAST(stats.reb AS FLOAT64) AS points_rebounds,
        CAST(stats.ast AS FLOAT64) AS assists,
        CAST(stats.pts AS FLOAT64) + CAST(stats.ast AS FLOAT64) AS points_assists,
        CAST(stats.reb AS FLOAT64) + CAST(stats.ast AS FLOAT64) AS rebounds_assists,
        CAST(stats.pts AS FLOAT64) + CAST(stats.reb AS FLOAT64) + CAST(stats.ast AS FLOAT64) AS points_rebounds_assists,
        CAST(stats.stl AS FLOAT64) AS steals,
        CAST(stats.blk AS FLOAT64) AS blocks,
        CAST(stats.blk AS FLOAT64) + CAST(stats.stl AS FLOAT64) AS blocks_steals,
        CAST(stats.tov AS FLOAT64) AS turnovers,

        -- Shooting statistics
        --CAST(stats.fgm AS FLOAT64) AS field_goals_made,
        --CAST(stats.fga AS FLOAT64) AS field_goals_attempted,
        CAST(stats.fg3m AS FLOAT64) AS three_pointers_made,
        --CAST(stats.fg3a AS FLOAT64) AS three_pointers_attempted,
        --CAST(stats.ftm AS FLOAT64) AS free_throws_made,
        --CAST(stats.fta AS FLOAT64) AS free_throws_attempted,

        CAST(stats.dd2 AS INTEGER) AS double_doubles,
        CAST(stats.td3 AS INTEGER) AS triple_doubles,

        CAST(stats.age AS INTEGER) AS age,
        -- Metadata
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data