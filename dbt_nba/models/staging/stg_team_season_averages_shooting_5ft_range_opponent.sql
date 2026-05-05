{{ config(
    description='Staging — % cedido pela defesa do time por faixa de distância (less_than_5_ft a 40_ft+). Source: balldontlie shooting/5ft_range_opponent. Filtrado para season_type = regular.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_shooting_5ft_range_opponent') }}
    WHERE season_type = 'regular'
)

SELECT
    CAST(team.id AS INT64) AS team_id,
    CAST(season AS INT64) AS season,
    season_type,

    -- Less than 5 ft
    CAST(stats.less_than_5_ft_opp_fga AS FLOAT64) AS opp_lt_5ft_fga,
    CAST(stats.less_than_5_ft_opp_fgm AS FLOAT64) AS opp_lt_5ft_fgm,
    CAST(stats.less_than_5_ft_opp_fg_pct AS FLOAT64) AS opp_lt_5ft_fg_pct,

    -- 5-9 ft
    CAST(stats.`_5_9_ft_opp_fga` AS FLOAT64) AS opp_5_9ft_fga,
    CAST(stats.`_5_9_ft_opp_fgm` AS FLOAT64) AS opp_5_9ft_fgm,
    CAST(stats.`_5_9_ft_opp_fg_pct` AS FLOAT64) AS opp_5_9ft_fg_pct,

    -- 10-14 ft
    CAST(stats.`_10_14_ft_opp_fga` AS FLOAT64) AS opp_10_14ft_fga,
    CAST(stats.`_10_14_ft_opp_fgm` AS FLOAT64) AS opp_10_14ft_fgm,
    CAST(stats.`_10_14_ft_opp_fg_pct` AS FLOAT64) AS opp_10_14ft_fg_pct,

    -- 15-19 ft
    CAST(stats.`_15_19_ft_opp_fga` AS FLOAT64) AS opp_15_19ft_fga,
    CAST(stats.`_15_19_ft_opp_fgm` AS FLOAT64) AS opp_15_19ft_fgm,
    CAST(stats.`_15_19_ft_opp_fg_pct` AS FLOAT64) AS opp_15_19ft_fg_pct,

    -- 20-24 ft
    CAST(stats.`_20_24_ft_opp_fga` AS FLOAT64) AS opp_20_24ft_fga,
    CAST(stats.`_20_24_ft_opp_fgm` AS FLOAT64) AS opp_20_24ft_fgm,
    CAST(stats.`_20_24_ft_opp_fg_pct` AS FLOAT64) AS opp_20_24ft_fg_pct,

    -- 25-29 ft
    CAST(stats.`_25_29_ft_opp_fga` AS FLOAT64) AS opp_25_29ft_fga,
    CAST(stats.`_25_29_ft_opp_fgm` AS FLOAT64) AS opp_25_29ft_fgm,
    CAST(stats.`_25_29_ft_opp_fg_pct` AS FLOAT64) AS opp_25_29ft_fg_pct,

    -- 30-34 ft
    CAST(stats.`_30_34_ft_opp_fga` AS FLOAT64) AS opp_30_34ft_fga,
    CAST(stats.`_30_34_ft_opp_fgm` AS FLOAT64) AS opp_30_34ft_fgm,
    CAST(stats.`_30_34_ft_opp_fg_pct` AS FLOAT64) AS opp_30_34ft_fg_pct,

    -- 35-39 ft
    CAST(stats.`_35_39_ft_opp_fga` AS FLOAT64) AS opp_35_39ft_fga,
    CAST(stats.`_35_39_ft_opp_fgm` AS FLOAT64) AS opp_35_39ft_fgm,
    CAST(stats.`_35_39_ft_opp_fg_pct` AS FLOAT64) AS opp_35_39ft_fg_pct,

    -- 40+ ft
    CAST(stats.`_40_ft_opp_fga` AS FLOAT64) AS opp_40ft_fga,
    CAST(stats.`_40_ft_opp_fgm` AS FLOAT64) AS opp_40ft_fgm,
    CAST(stats.`_40_ft_opp_fg_pct` AS FLOAT64) AS opp_40ft_fg_pct
FROM source_data
