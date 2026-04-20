{{
  config(
    description='NBA team opponent stats rankings. One row per team with stats conceded per game and pre-computed rankings (1=best defense, 30=worst defense for each category).',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH standings AS (
    SELECT team_id, team_name, team_abbreviation, season
    FROM {{ ref('stg_team_standings') }}
),

opp AS (
    SELECT * FROM {{ ref('stg_team_season_averages_general_opponent') }}
),

defense AS (
    SELECT * FROM {{ ref('stg_team_season_averages_general_defense') }}
),

tracking_reb AS (
    SELECT * FROM {{ ref('stg_team_season_averages_tracking_rebounding') }}
),

catchshoot AS (
    SELECT * FROM {{ ref('stg_team_season_averages_shotdashboard_catchshoot') }}
),

pullups AS (
    SELECT * FROM {{ ref('stg_team_season_averages_shotdashboard_pullups') }}
),

tracking_def AS (
    SELECT *,
        RANK() OVER (PARTITION BY season ORDER BY def_rim_fg_pct ASC) AS def_rim_fg_pct_rank
    FROM {{ ref('stg_team_season_averages_tracking_defense') }}
)

SELECT
    s.team_id,
    s.team_name,
    s.team_abbreviation,
    s.season,

    -- Points conceded (rank 30 = most pts conceded = weakest defense for pts props)
    o.opp_pts,
    o.opp_pts_rank,

    -- Rebounds conceded
    o.opp_reb,
    o.opp_reb_rank,
    o.opp_oreb,
    o.opp_oreb_rank,
    o.opp_dreb,
    o.opp_dreb_rank,

    -- Assists conceded
    o.opp_ast,
    o.opp_ast_rank,

    -- FG% conceded
    o.opp_fg_pct,
    o.opp_fg_pct_rank,

    -- 3P% conceded
    o.opp_fg3_pct,
    o.opp_fg3_pct_rank,

    -- Steals / Blocks / Turnovers conceded
    o.opp_stl,
    o.opp_stl_rank,
    o.opp_blk,
    o.opp_blk_rank,
    o.opp_tov,
    o.opp_tov_rank,

    -- Free throws conceded
    o.opp_fta,
    o.opp_fta_rank,
    o.opp_ft_pct,
    o.opp_ft_pct_rank,

    -- Advanced defense (from general/defense)
    d.def_rating,
    d.def_rating_rank,
    d.opp_pts_paint,
    d.opp_pts_paint_rank,
    d.opp_pts_2nd_chance,
    d.opp_pts_2nd_chance_rank,
    d.opp_pts_off_tov,
    d.opp_pts_off_tov_rank,
    d.opp_pts_fb,
    d.opp_pts_fb_rank,
    d.dreb_pct,
    d.dreb_pct_rank,

    -- Rebounding tracking (chance rates and contest rates)
    tr.oreb_chance_pct,
    tr.dreb_chance_pct,
    tr.reb_chance_pct,
    tr.oreb_chances,
    tr.dreb_chances,
    tr.oreb_contest_pct,
    tr.dreb_contest_pct,
    tr.avg_reb_dist,

    -- Catch & Shoot profile
    cs.fga AS cs_fga,
    cs.fga_frequency AS cs_fga_frequency,
    cs.fg3a AS cs_fg3a,
    cs.fg3a_frequency AS cs_fg3a_frequency,
    cs.fg_pct AS cs_fg_pct,
    cs.fg3_pct AS cs_fg3_pct,
    cs.efg_pct AS cs_efg_pct,

    -- Pull-Up profile
    pu.fga AS pullup_fga,
    pu.fga_frequency AS pullup_fga_frequency,
    pu.fg3a AS pullup_fg3a,
    pu.fg3a_frequency AS pullup_fg3a_frequency,
    pu.fg_pct AS pullup_fg_pct,
    pu.fg3_pct AS pullup_fg3_pct,
    pu.efg_pct AS pullup_efg_pct,

    -- Rim protection (tracking defense)
    td.def_rim_fga,
    td.def_rim_fgm,
    td.def_rim_fg_pct,
    td.def_rim_fg_pct_rank,

    CURRENT_TIMESTAMP() AS loaded_at

FROM standings s
LEFT JOIN opp o ON s.team_id = o.team_id AND s.season = o.season
LEFT JOIN defense d ON s.team_id = d.team_id AND s.season = d.season
LEFT JOIN tracking_reb tr ON s.team_id = tr.team_id AND s.season = tr.season
LEFT JOIN catchshoot cs ON s.team_id = cs.team_id AND s.season = cs.season
LEFT JOIN pullups pu ON s.team_id = pu.team_id AND s.season = pu.season
LEFT JOIN tracking_def td ON s.team_id = td.team_id AND s.season = td.season
