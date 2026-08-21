

WITH source_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`raw_team_season_averages_shooting_by_zone_opponent`
    WHERE season_type = 'regular'
)

SELECT
    CAST(team.id AS INT64) AS team_id,
    CAST(season AS INT64) AS season,
    season_type,

    -- Restricted area
    CAST(stats.restricted_area_opp_fga AS FLOAT64) AS opp_restricted_area_fga,
    CAST(stats.restricted_area_opp_fgm AS FLOAT64) AS opp_restricted_area_fgm,
    CAST(stats.restricted_area_opp_fg_pct AS FLOAT64) AS opp_restricted_area_fg_pct,

    -- Paint non-RA
    CAST(stats.in_the_paint_non_ra_opp_fga AS FLOAT64) AS opp_in_the_paint_non_ra_fga,
    CAST(stats.in_the_paint_non_ra_opp_fgm AS FLOAT64) AS opp_in_the_paint_non_ra_fgm,
    CAST(stats.in_the_paint_non_ra_opp_fg_pct AS FLOAT64) AS opp_in_the_paint_non_ra_fg_pct,

    -- Mid-range
    CAST(stats.mid_range_opp_fga AS FLOAT64) AS opp_mid_range_fga,
    CAST(stats.mid_range_opp_fgm AS FLOAT64) AS opp_mid_range_fgm,
    CAST(stats.mid_range_opp_fg_pct AS FLOAT64) AS opp_mid_range_fg_pct,

    -- Left corner 3
    CAST(stats.left_corner_3_opp_fga AS FLOAT64) AS opp_left_corner_3_fga,
    CAST(stats.left_corner_3_opp_fgm AS FLOAT64) AS opp_left_corner_3_fgm,
    CAST(stats.left_corner_3_opp_fg_pct AS FLOAT64) AS opp_left_corner_3_fg_pct,

    -- Right corner 3
    CAST(stats.right_corner_3_opp_fga AS FLOAT64) AS opp_right_corner_3_fga,
    CAST(stats.right_corner_3_opp_fgm AS FLOAT64) AS opp_right_corner_3_fgm,
    CAST(stats.right_corner_3_opp_fg_pct AS FLOAT64) AS opp_right_corner_3_fg_pct,

    -- Corner 3 agregado
    CAST(stats.corner_3_opp_fga AS FLOAT64) AS opp_corner_3_fga,
    CAST(stats.corner_3_opp_fgm AS FLOAT64) AS opp_corner_3_fgm,
    CAST(stats.corner_3_opp_fg_pct AS FLOAT64) AS opp_corner_3_fg_pct,

    -- Above the break 3
    CAST(stats.above_the_break_3_opp_fga AS FLOAT64) AS opp_above_the_break_3_fga,
    CAST(stats.above_the_break_3_opp_fgm AS FLOAT64) AS opp_above_the_break_3_fgm,
    CAST(stats.above_the_break_3_opp_fg_pct AS FLOAT64) AS opp_above_the_break_3_fg_pct,

    -- Backcourt
    CAST(stats.backcourt_opp_fga AS FLOAT64) AS opp_backcourt_fga,
    CAST(stats.backcourt_opp_fgm AS FLOAT64) AS opp_backcourt_fgm,
    CAST(stats.backcourt_opp_fg_pct AS FLOAT64) AS opp_backcourt_fg_pct
FROM source_data