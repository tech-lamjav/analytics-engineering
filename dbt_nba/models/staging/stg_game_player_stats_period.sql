{{ config(
    description='Staging for NBA game player stats by period (quarter/half) from NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_game_player_stats_period') }}
    WHERE CAST(period AS INTEGER) IN (1, 2)
),

unnested AS (
    SELECT
        CAST(src.period AS INTEGER) AS period,
        stat
    FROM source_data AS src,
    UNNEST(src.stats) AS stat
),

cleaned_data AS (
    SELECT
        period,
        CAST(stat.player.id AS INT64) AS player_id,
        CAST(stat.team.id   AS INT64) AS team_id,
        CAST(stat.game.id   AS INT64) AS game_id,
        SAFE_CAST(stat.game.date AS DATE) AS game_date,
        SAFE_CAST(stat.pts       AS INTEGER) AS points,
        SAFE_CAST(stat.min       AS INTEGER) AS minutes,
        SAFE_CAST(stat.reb       AS INTEGER) AS rebounds,
        SAFE_CAST(stat.ast       AS INTEGER) AS assists
    FROM unnested
)

SELECT * FROM cleaned_data
