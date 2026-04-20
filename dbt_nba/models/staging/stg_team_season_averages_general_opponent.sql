{{ config(
    description='Staging table for NBA team season averages (general/opponent). Stats that each team concedes to opponents with pre-computed rankings from Balldontlie API.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_general_opponent') }}
    WHERE season_type = 'regular'
),

cleaned_data AS (
    SELECT
        CAST(team.id AS INT64) AS team_id,
        CAST(season AS INT64) AS season,
        season_type,
        CAST(stats.opp_pts AS FLOAT64) AS opp_pts,
        CAST(stats.opp_pts_rank AS INT64) AS opp_pts_rank,
        CAST(stats.opp_reb AS FLOAT64) AS opp_reb,
        CAST(stats.opp_reb_rank AS INT64) AS opp_reb_rank,
        CAST(stats.opp_ast AS FLOAT64) AS opp_ast,
        CAST(stats.opp_ast_rank AS INT64) AS opp_ast_rank,
        CAST(stats.opp_fg_pct AS FLOAT64) AS opp_fg_pct,
        CAST(stats.opp_fg_pct_rank AS INT64) AS opp_fg_pct_rank,
        CAST(stats.opp_fg3_pct AS FLOAT64) AS opp_fg3_pct,
        CAST(stats.opp_fg3_pct_rank AS INT64) AS opp_fg3_pct_rank,
        CAST(stats.opp_oreb AS FLOAT64) AS opp_oreb,
        CAST(stats.opp_oreb_rank AS INT64) AS opp_oreb_rank,
        CAST(stats.opp_dreb AS FLOAT64) AS opp_dreb,
        CAST(stats.opp_dreb_rank AS INT64) AS opp_dreb_rank,
        CAST(stats.opp_stl AS FLOAT64) AS opp_stl,
        CAST(stats.opp_stl_rank AS INT64) AS opp_stl_rank,
        CAST(stats.opp_blk AS FLOAT64) AS opp_blk,
        CAST(stats.opp_blk_rank AS INT64) AS opp_blk_rank,
        CAST(stats.opp_tov AS FLOAT64) AS opp_tov,
        CAST(stats.opp_tov_rank AS INT64) AS opp_tov_rank,
        CAST(stats.opp_fta AS FLOAT64) AS opp_fta,
        CAST(stats.opp_fta_rank AS INT64) AS opp_fta_rank,
        CAST(stats.opp_ft_pct AS FLOAT64) AS opp_ft_pct,
        CAST(stats.opp_ft_pct_rank AS INT64) AS opp_ft_pct_rank,
    FROM source_data
)

SELECT * FROM cleaned_data
