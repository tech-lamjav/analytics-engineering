{{ config(
    description='Staging table for NBA game player stats from NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_game_player_stats') }}
    WHERE season = 2025
),

unnested AS (
    SELECT
        season,
        stat
    FROM source_data,
    UNNEST(stats) AS stat
),

cleaned_data AS (
    SELECT
        stat.player.id AS player_id,
        stat.team.id AS team_id,
        stat.game.id AS game_id,
        stat.game.date AS game_date,
        season,
        stat.game.home_team_score,
        stat.game.home_team_id,
        stat.game.visitor_team_score,
        stat.game.visitor_team_id,
        CAST(stat.pts AS INTEGER) AS points,
        CAST(stat.min AS INTEGER) AS minutes,
        CAST(stat.fg3m AS INTEGER) AS threes,
        CAST(stat.reb AS INTEGER) AS rebounds,
        CAST(stat.pts AS INTEGER) + CAST(stat.reb AS INTEGER) AS points_rebounds,
        CAST(stat.ast AS INTEGER) AS assists,
        CAST(stat.pts AS INTEGER) + CAST(stat.ast AS INTEGER) AS points_assists,
        CAST(stat.reb AS INTEGER) + CAST(stat.ast AS INTEGER) AS rebounds_assists,
        CAST(stat.oreb AS INTEGER) AS offensive_rebounds,
        CAST(stat.dreb AS INTEGER) AS defensive_rebounds,
        CAST(stat.pts AS INTEGER) + CAST(stat.reb AS INTEGER) + CAST(stat.ast AS INTEGER) AS points_rebounds_assists,
        CAST(stat.stl AS INTEGER) AS steals,
        CAST(stat.blk AS INTEGER) AS blocks,
        CAST(stat.blk AS INTEGER) + CAST(stat.stl AS INTEGER) AS blocks_steals,
        CAST(stat.turnover AS INTEGER) AS turnovers,
        CAST(stat.fg_pct AS FLOAT64) AS field_goal_percentage,
        CAST(stat.ft_pct AS FLOAT64) AS free_throw_percentage,
        CAST(stat.plus_minus AS INTEGER) AS plus_minus,
        CASE
            WHEN (
                (CAST(CAST(stat.pts AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.reb AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.ast AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.stl AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.blk AS INTEGER) > 10 AS INT64))
            ) >= 3 THEN 1
            ELSE 0
        END AS triple_double,
        CASE
            WHEN (
                (CAST(CAST(stat.pts AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.reb AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.ast AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.stl AS INTEGER) > 10 AS INT64))
                + (CAST(CAST(stat.blk AS INTEGER) > 10 AS INT64))
            ) >= 2 THEN 1
            ELSE 0
        END AS double_double,
        CASE
            WHEN stat.game.home_team_score > stat.game.visitor_team_score THEN stat.game.home_team_id
            WHEN stat.game.visitor_team_score > stat.game.home_team_score THEN stat.game.visitor_team_id
        END AS winner_team_id,
        ROW_NUMBER() OVER (PARTITION BY stat.player.id ORDER BY stat.game.id DESC) AS game_number
    FROM unnested
    WHERE stat.min IS NOT NULL AND SAFE_CAST(stat.min AS INTEGER) > 0
)

SELECT * FROM cleaned_data
