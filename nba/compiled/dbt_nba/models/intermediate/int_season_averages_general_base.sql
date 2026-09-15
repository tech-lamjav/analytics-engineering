

WITH base_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`stg_season_averages_general_base`
),

-- Unpivot the specified stats into long format
stats_unpivoted AS (
    SELECT
        player_id,
        'player_points' AS stat_type,
        points AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_rebounds' AS stat_type,
        rebounds AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_assists' AS stat_type,
        assists AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_steals' AS stat_type,
        steals AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_blocks' AS stat_type,
        blocks AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_turnovers' AS stat_type,
        turnovers AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_threes' AS stat_type,
        three_pointers_made AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_points_rebounds' AS stat_type,
        points_rebounds AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_points_assists' AS stat_type,
        points_assists AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_rebounds_assists' AS stat_type,
        rebounds_assists AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_points_rebounds_assists' AS stat_type,
        points_rebounds_assists AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_blocks_steals' AS stat_type,
        blocks_steals AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_double_double' AS stat_type,
        CAST(double_doubles AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        'player_triple_double' AS stat_type,
        CAST(triple_doubles AS FLOAT64) AS stat_value
    FROM base_data
)

SELECT *
FROM stats_unpivoted