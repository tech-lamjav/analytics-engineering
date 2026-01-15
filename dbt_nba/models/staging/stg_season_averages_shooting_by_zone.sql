{{ config(
    description='Staging table for NBA season averages (shooting/by_zone) from NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_season_averages_shooting_by_zone') }}
),

cleaned_data AS (
    SELECT
        -- Player information
        player.id AS player_id,
        TRIM(player.first_name || ' ' || player.last_name) AS player_name,

        -- Corner 3-point statistics
        CAST(stats.corner_3_fga AS FLOAT64) AS corner_3_fga,
        CAST(stats.corner_3_fgm AS FLOAT64) AS corner_3_fgm,
        CAST(stats.corner_3_fg_pct AS FLOAT64) AS corner_3_fg_pct,
        CAST(stats.left_corner_3_fga AS FLOAT64) AS left_corner_3_fga,
        CAST(stats.left_corner_3_fgm AS FLOAT64) AS left_corner_3_fgm,
        CAST(stats.left_corner_3_fg_pct AS FLOAT64) AS left_corner_3_fg_pct,
        CAST(stats.right_corner_3_fga AS FLOAT64) AS right_corner_3_fga,
        CAST(stats.right_corner_3_fgm AS FLOAT64) AS right_corner_3_fgm,
        CAST(stats.right_corner_3_fg_pct AS FLOAT64) AS right_corner_3_fg_pct,

        -- Above the break 3-point statistics
        CAST(stats.above_the_break_3_fga AS FLOAT64) AS above_the_break_3_fga,
        CAST(stats.above_the_break_3_fgm AS FLOAT64) AS above_the_break_3_fgm,
        CAST(stats.above_the_break_3_fg_pct AS FLOAT64) AS above_the_break_3_fg_pct,

        -- Restricted area statistics
        CAST(stats.restricted_area_fga AS FLOAT64) AS restricted_area_fga,
        CAST(stats.restricted_area_fgm AS FLOAT64) AS restricted_area_fgm,
        CAST(stats.restricted_area_fg_pct AS FLOAT64) AS restricted_area_fg_pct,

        -- In the paint (non-restricted area) statistics
        CAST(stats.in_the_paint_non_ra_fga AS FLOAT64) AS in_the_paint_non_ra_fga,
        CAST(stats.in_the_paint_non_ra_fgm AS FLOAT64) AS in_the_paint_non_ra_fgm,
        CAST(stats.in_the_paint_non_ra_fg_pct AS FLOAT64) AS in_the_paint_non_ra_fg_pct,

        -- Mid-range statistics
        CAST(stats.mid_range_fga AS FLOAT64) AS mid_range_fga,
        CAST(stats.mid_range_fgm AS FLOAT64) AS mid_range_fgm,
        CAST(stats.mid_range_fg_pct AS FLOAT64) AS mid_range_fg_pct,

        -- Backcourt statistics
        CAST(stats.backcourt_fga AS FLOAT64) AS backcourt_fga,
        CAST(stats.backcourt_fgm AS FLOAT64) AS backcourt_fgm,
        CAST(stats.backcourt_fg_pct AS FLOAT64) AS backcourt_fg_pct,

        -- Metadata
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data
