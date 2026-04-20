{{ config(
    description='Intermediate model that pilled game player stats'
) }}

WITH base_data AS (
    SELECT * FROM {{ ref('stg_game_player_stats') }}
    WHERE
        minutes > 0
),

-- Pilled the specified stats
stats_pilled AS (
    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_points' AS stat_type,
        CAST(points AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_threes' AS stat_type,
        CAST(threes AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_rebounds' AS stat_type,
        CAST(rebounds AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_assists' AS stat_type,
        CAST(assists AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_blocks' AS stat_type,
        CAST(blocks AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_steals' AS stat_type,
        CAST(steals AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_turnovers' AS stat_type,
        CAST(turnovers AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_points_rebounds' AS stat_type,
        CAST(points_rebounds AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_points_assists' AS stat_type,
        CAST(points_assists AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_rebounds_assists' AS stat_type,
        CAST(rebounds_assists AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_points_rebounds_assists' AS stat_type,
        CAST(points_rebounds_assists AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_blocks_steals' AS stat_type,
        CAST(blocks_steals AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_double_double' AS stat_type,
        CAST(double_double AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_triple_double' AS stat_type,
        CAST(triple_double AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_offensive_rebounds' AS stat_type,
        CAST(offensive_rebounds AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_defensive_rebounds' AS stat_type,
        CAST(defensive_rebounds AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_field_goal_percentage' AS stat_type,
        CAST(field_goal_percentage AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_free_throw_percentage' AS stat_type,
        CAST(free_throw_percentage AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_minutes' AS stat_type,
        CAST(minutes AS FLOAT64) AS stat_value
    FROM base_data

    UNION ALL

    SELECT
        player_id,
        team_id,
        game_id,
        game_number,
        game_date,
        'player_plus_minus' AS stat_type,
        CAST(plus_minus AS FLOAT64) AS stat_value
    FROM base_data
)

SELECT
    sp.player_id,
    sp.team_id,
    sp.game_id,
    sp.game_number,
    sp.game_date,
    bd.season,
    sp.stat_type,
    sp.stat_value,
FROM stats_pilled sp
LEFT JOIN (
    SELECT DISTINCT game_id, player_id, season FROM base_data
) bd ON sp.game_id = bd.game_id AND sp.player_id = bd.player_id