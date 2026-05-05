{{
  config(
    description='NBA team play type breakdown. One row per team with offensive PPP, possession frequency, eFG% and rank for each of the 10 play types. ppp_rank: 1 = highest PPP (most efficient offense in that play type).',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH base AS (
    SELECT * FROM {{ ref('stg_team_season_averages_playtypes') }}
),

standings AS (
    SELECT team_id, team_name, team_abbreviation, season
    FROM {{ ref('stg_team_standings') }}
),

ranked AS (
    SELECT *,
        RANK() OVER (PARTITION BY season, play_type ORDER BY ppp DESC) AS ppp_rank
    FROM base
)

SELECT
    s.team_id,
    s.team_name,
    s.team_abbreviation,
    s.season,

    -- Isolation
    MAX(IF(play_type = 'isolation', ppp, NULL)) AS iso_ppp,
    MAX(IF(play_type = 'isolation', poss_pct, NULL)) AS iso_poss_pct,
    MAX(IF(play_type = 'isolation', efg_pct, NULL)) AS iso_efg_pct,
    MAX(IF(play_type = 'isolation', percentile, NULL)) AS iso_percentile,
    MAX(IF(play_type = 'isolation', CAST(ppp_rank AS INT64), NULL)) AS iso_ppp_rank,

    -- Spot Up
    MAX(IF(play_type = 'spotup', ppp, NULL)) AS spotup_ppp,
    MAX(IF(play_type = 'spotup', poss_pct, NULL)) AS spotup_poss_pct,
    MAX(IF(play_type = 'spotup', efg_pct, NULL)) AS spotup_efg_pct,
    MAX(IF(play_type = 'spotup', percentile, NULL)) AS spotup_percentile,
    MAX(IF(play_type = 'spotup', CAST(ppp_rank AS INT64), NULL)) AS spotup_ppp_rank,

    -- PnR Ball Handler
    MAX(IF(play_type = 'prballhandler', ppp, NULL)) AS pnr_bh_ppp,
    MAX(IF(play_type = 'prballhandler', poss_pct, NULL)) AS pnr_bh_poss_pct,
    MAX(IF(play_type = 'prballhandler', efg_pct, NULL)) AS pnr_bh_efg_pct,
    MAX(IF(play_type = 'prballhandler', percentile, NULL)) AS pnr_bh_percentile,
    MAX(IF(play_type = 'prballhandler', CAST(ppp_rank AS INT64), NULL)) AS pnr_bh_ppp_rank,

    -- PnR Roll Man
    MAX(IF(play_type = 'prrollman', ppp, NULL)) AS pnr_rm_ppp,
    MAX(IF(play_type = 'prrollman', poss_pct, NULL)) AS pnr_rm_poss_pct,
    MAX(IF(play_type = 'prrollman', efg_pct, NULL)) AS pnr_rm_efg_pct,
    MAX(IF(play_type = 'prrollman', percentile, NULL)) AS pnr_rm_percentile,
    MAX(IF(play_type = 'prrollman', CAST(ppp_rank AS INT64), NULL)) AS pnr_rm_ppp_rank,

    -- Post Up
    MAX(IF(play_type = 'postup', ppp, NULL)) AS postup_ppp,
    MAX(IF(play_type = 'postup', poss_pct, NULL)) AS postup_poss_pct,
    MAX(IF(play_type = 'postup', efg_pct, NULL)) AS postup_efg_pct,
    MAX(IF(play_type = 'postup', percentile, NULL)) AS postup_percentile,
    MAX(IF(play_type = 'postup', CAST(ppp_rank AS INT64), NULL)) AS postup_ppp_rank,

    -- Transition
    MAX(IF(play_type = 'transition', ppp, NULL)) AS transition_ppp,
    MAX(IF(play_type = 'transition', poss_pct, NULL)) AS transition_poss_pct,
    MAX(IF(play_type = 'transition', efg_pct, NULL)) AS transition_efg_pct,
    MAX(IF(play_type = 'transition', percentile, NULL)) AS transition_percentile,
    MAX(IF(play_type = 'transition', CAST(ppp_rank AS INT64), NULL)) AS transition_ppp_rank,

    -- Handoff
    MAX(IF(play_type = 'handoff', ppp, NULL)) AS handoff_ppp,
    MAX(IF(play_type = 'handoff', poss_pct, NULL)) AS handoff_poss_pct,
    MAX(IF(play_type = 'handoff', efg_pct, NULL)) AS handoff_efg_pct,
    MAX(IF(play_type = 'handoff', percentile, NULL)) AS handoff_percentile,
    MAX(IF(play_type = 'handoff', CAST(ppp_rank AS INT64), NULL)) AS handoff_ppp_rank,

    -- Cut
    MAX(IF(play_type = 'cut', ppp, NULL)) AS cut_ppp,
    MAX(IF(play_type = 'cut', poss_pct, NULL)) AS cut_poss_pct,
    MAX(IF(play_type = 'cut', efg_pct, NULL)) AS cut_efg_pct,
    MAX(IF(play_type = 'cut', percentile, NULL)) AS cut_percentile,
    MAX(IF(play_type = 'cut', CAST(ppp_rank AS INT64), NULL)) AS cut_ppp_rank,

    -- Off Screen
    MAX(IF(play_type = 'offscreen', ppp, NULL)) AS offscreen_ppp,
    MAX(IF(play_type = 'offscreen', poss_pct, NULL)) AS offscreen_poss_pct,
    MAX(IF(play_type = 'offscreen', efg_pct, NULL)) AS offscreen_efg_pct,
    MAX(IF(play_type = 'offscreen', percentile, NULL)) AS offscreen_percentile,
    MAX(IF(play_type = 'offscreen', CAST(ppp_rank AS INT64), NULL)) AS offscreen_ppp_rank,

    -- Off Rebound (Putback)
    MAX(IF(play_type = 'offrebound', ppp, NULL)) AS putback_ppp,
    MAX(IF(play_type = 'offrebound', poss_pct, NULL)) AS putback_poss_pct,
    MAX(IF(play_type = 'offrebound', efg_pct, NULL)) AS putback_efg_pct,
    MAX(IF(play_type = 'offrebound', percentile, NULL)) AS putback_percentile,
    MAX(IF(play_type = 'offrebound', CAST(ppp_rank AS INT64), NULL)) AS putback_ppp_rank,

    CURRENT_TIMESTAMP() AS loaded_at

FROM standings s
LEFT JOIN ranked r ON s.team_id = r.team_id AND s.season = r.season
GROUP BY s.team_id, s.team_name, s.team_abbreviation, s.season
