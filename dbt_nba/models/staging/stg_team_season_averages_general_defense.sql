{{ config(
    description='Staging table for NBA team season averages (general/defense). Defensive metrics including DefRtg, paint points conceded, 2nd chance points conceded, from Balldontlie API.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_general_defense') }}
    WHERE season_type = 'regular'
),

cleaned_data AS (
    SELECT
        CAST(team.id AS INT64) AS team_id,
        CAST(season AS INT64) AS season,
        season_type,
        CAST(stats.def_rating AS FLOAT64) AS def_rating,
        CAST(stats.def_rating_rank AS INT64) AS def_rating_rank,
        CAST(stats.opp_pts_paint AS FLOAT64) AS opp_pts_paint,
        CAST(stats.opp_pts_paint_rank AS INT64) AS opp_pts_paint_rank,
        CAST(stats.opp_pts_2nd_chance AS FLOAT64) AS opp_pts_2nd_chance,
        CAST(stats.opp_pts_2nd_chance_rank AS INT64) AS opp_pts_2nd_chance_rank,
        CAST(stats.opp_pts_off_tov AS FLOAT64) AS opp_pts_off_tov,
        CAST(stats.opp_pts_off_tov_rank AS INT64) AS opp_pts_off_tov_rank,
        CAST(stats.opp_pts_fb AS FLOAT64) AS opp_pts_fb,
        CAST(stats.opp_pts_fb_rank AS INT64) AS opp_pts_fb_rank,
        CAST(stats.dreb_pct AS FLOAT64) AS dreb_pct,
        CAST(stats.dreb_pct_rank AS INT64) AS dreb_pct_rank,
        CAST(stats.stl AS FLOAT64) AS stl,
        CAST(stats.stl_rank AS INT64) AS stl_rank,
        CAST(stats.blk AS FLOAT64) AS blk,
        CAST(stats.blk_rank AS INT64) AS blk_rank,
    FROM source_data
)

SELECT * FROM cleaned_data
