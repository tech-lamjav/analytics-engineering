{{
  config(
    description='Defesa por zona de arremesso e faixa de distância. % cedido pela defesa do time, com rankings calculados localmente (rank 1 = menor FG% cedido = melhor defesa).',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH standings AS (
    SELECT team_id, team_name, team_abbreviation, season
    FROM {{ ref('stg_team_standings') }}
),

zone AS (
    SELECT *,
        RANK() OVER (PARTITION BY season ORDER BY opp_restricted_area_fg_pct ASC) AS opp_restricted_area_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_in_the_paint_non_ra_fg_pct ASC) AS opp_in_the_paint_non_ra_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_mid_range_fg_pct ASC) AS opp_mid_range_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_corner_3_fg_pct ASC) AS opp_corner_3_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_above_the_break_3_fg_pct ASC) AS opp_above_the_break_3_fg_pct_rank
    FROM {{ ref('stg_team_season_averages_shooting_by_zone_opponent') }}
),

range5 AS (
    SELECT *,
        RANK() OVER (PARTITION BY season ORDER BY opp_lt_5ft_fg_pct ASC) AS opp_lt_5ft_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_5_9ft_fg_pct ASC) AS opp_5_9ft_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_10_14ft_fg_pct ASC) AS opp_10_14ft_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_15_19ft_fg_pct ASC) AS opp_15_19ft_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_20_24ft_fg_pct ASC) AS opp_20_24ft_fg_pct_rank,
        RANK() OVER (PARTITION BY season ORDER BY opp_25_29ft_fg_pct ASC) AS opp_25_29ft_fg_pct_rank
    FROM {{ ref('stg_team_season_averages_shooting_5ft_range_opponent') }}
)

SELECT
    s.team_id,
    s.team_name,
    s.team_abbreviation,
    s.season,

    -- Restricted area
    z.opp_restricted_area_fga,
    z.opp_restricted_area_fgm,
    z.opp_restricted_area_fg_pct,
    z.opp_restricted_area_fg_pct_rank,

    -- Paint non-RA
    z.opp_in_the_paint_non_ra_fga,
    z.opp_in_the_paint_non_ra_fgm,
    z.opp_in_the_paint_non_ra_fg_pct,
    z.opp_in_the_paint_non_ra_fg_pct_rank,

    -- Mid-range
    z.opp_mid_range_fga,
    z.opp_mid_range_fgm,
    z.opp_mid_range_fg_pct,
    z.opp_mid_range_fg_pct_rank,

    -- Corner 3 (agregado + L/R)
    z.opp_corner_3_fga,
    z.opp_corner_3_fgm,
    z.opp_corner_3_fg_pct,
    z.opp_corner_3_fg_pct_rank,
    z.opp_left_corner_3_fga,
    z.opp_left_corner_3_fgm,
    z.opp_left_corner_3_fg_pct,
    z.opp_right_corner_3_fga,
    z.opp_right_corner_3_fgm,
    z.opp_right_corner_3_fg_pct,

    -- Above the break 3
    z.opp_above_the_break_3_fga,
    z.opp_above_the_break_3_fgm,
    z.opp_above_the_break_3_fg_pct,
    z.opp_above_the_break_3_fg_pct_rank,

    -- Backcourt (sem rank — volume desprezível)
    z.opp_backcourt_fga,
    z.opp_backcourt_fgm,
    z.opp_backcourt_fg_pct,

    -- Faixas de distância (rank apenas para faixas com volume relevante: 0-29ft)
    r.opp_lt_5ft_fga,    r.opp_lt_5ft_fgm,    r.opp_lt_5ft_fg_pct,    r.opp_lt_5ft_fg_pct_rank,
    r.opp_5_9ft_fga,     r.opp_5_9ft_fgm,     r.opp_5_9ft_fg_pct,     r.opp_5_9ft_fg_pct_rank,
    r.opp_10_14ft_fga,   r.opp_10_14ft_fgm,   r.opp_10_14ft_fg_pct,   r.opp_10_14ft_fg_pct_rank,
    r.opp_15_19ft_fga,   r.opp_15_19ft_fgm,   r.opp_15_19ft_fg_pct,   r.opp_15_19ft_fg_pct_rank,
    r.opp_20_24ft_fga,   r.opp_20_24ft_fgm,   r.opp_20_24ft_fg_pct,   r.opp_20_24ft_fg_pct_rank,
    r.opp_25_29ft_fga,   r.opp_25_29ft_fgm,   r.opp_25_29ft_fg_pct,   r.opp_25_29ft_fg_pct_rank,
    r.opp_30_34ft_fga,   r.opp_30_34ft_fgm,   r.opp_30_34ft_fg_pct,
    r.opp_35_39ft_fga,   r.opp_35_39ft_fgm,   r.opp_35_39ft_fg_pct,
    r.opp_40ft_fga,      r.opp_40ft_fgm,      r.opp_40ft_fg_pct,

    CURRENT_TIMESTAMP() AS loaded_at
FROM standings s
LEFT JOIN zone z ON s.team_id = z.team_id AND s.season = z.season
LEFT JOIN range5 r ON s.team_id = r.team_id AND s.season = r.season
