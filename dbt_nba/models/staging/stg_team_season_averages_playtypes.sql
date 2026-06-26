{{ config(
    description='Staging view for NBA team season averages play types (isolation, spotup, prballhandler, prrollman, postup, transition, handoff, cut, offscreen, offrebound). One row per team/play_type from Balldontlie API.'
) }}

WITH isolation AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_isolation') }}
    WHERE season_type = 'regular'
),
spotup AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_spotup') }}
    WHERE season_type = 'regular'
),
prballhandler AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_prballhandler') }}
    WHERE season_type = 'regular'
),
prrollman AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_prrollman') }}
    WHERE season_type = 'regular'
),
postup AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_postup') }}
    WHERE season_type = 'regular'
),
transition AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_transition') }}
    WHERE season_type = 'regular'
),
handoff AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_handoff') }}
    WHERE season_type = 'regular'
),
cut AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_cut') }}
    WHERE season_type = 'regular'
),
offscreen AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_offscreen') }}
    WHERE season_type = 'regular'
),
offrebound AS (
    SELECT team, season, season_type, type, stats FROM {{ source('nba', 'raw_team_season_averages_playtype_offrebound') }}
    WHERE season_type = 'regular'
),
all_playtypes AS (
    SELECT * FROM isolation
    UNION ALL SELECT * FROM spotup
    UNION ALL SELECT * FROM prballhandler
    UNION ALL SELECT * FROM prrollman
    UNION ALL SELECT * FROM postup
    UNION ALL SELECT * FROM transition
    UNION ALL SELECT * FROM handoff
    UNION ALL SELECT * FROM cut
    UNION ALL SELECT * FROM offscreen
    UNION ALL SELECT * FROM offrebound
)

SELECT
    CAST(team.id AS INT64) AS team_id,
    CAST(season AS INT64) AS season,
    season_type,
    type AS play_type,
    CAST(stats.ppp AS FLOAT64) AS ppp,
    CAST(stats.poss_pct AS FLOAT64) AS poss_pct,
    CAST(stats.efg_pct AS FLOAT64) AS efg_pct,
    CAST(stats.percentile AS FLOAT64) AS percentile,
    CAST(stats.pts AS FLOAT64) AS pts,
    CAST(stats.poss AS FLOAT64) AS poss,
    CAST(stats.fga AS FLOAT64) AS fga,
    CAST(stats.fg_pct AS FLOAT64) AS fg_pct,
    CAST(stats.fgm AS FLOAT64) AS fgm,
    CAST(stats.score_poss_pct AS FLOAT64) AS score_poss_pct,
    CAST(stats.tov_poss_pct AS FLOAT64) AS tov_poss_pct,
    CAST(stats.ft_poss_pct AS FLOAT64) AS ft_poss_pct,
    CAST(stats.gp AS INT64) AS games_played
FROM all_playtypes
