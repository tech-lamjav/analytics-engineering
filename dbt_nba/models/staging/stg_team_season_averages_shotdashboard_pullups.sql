{{ config(
    description='Staging view for NBA team season averages shot dashboard pull-ups. Team pull-up shooting profile from Balldontlie API.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_shotdashboard_pullups') }}
    WHERE season_type = 'regular'
)

SELECT
    CAST(team.id AS INT64) AS team_id,
    CAST(season AS INT64) AS season,
    season_type,
    CAST(stats.fga AS FLOAT64) AS fga,
    CAST(stats.fga_frequency AS FLOAT64) AS fga_frequency,
    CAST(stats.fg3a AS FLOAT64) AS fg3a,
    CAST(stats.fg3a_frequency AS FLOAT64) AS fg3a_frequency,
    CAST(stats.fg2a AS FLOAT64) AS fg2a,
    CAST(stats.fg2a_frequency AS FLOAT64) AS fg2a_frequency,
    CAST(stats.fgm AS FLOAT64) AS fgm,
    CAST(stats.fg3m AS FLOAT64) AS fg3m,
    CAST(stats.fg2m AS FLOAT64) AS fg2m,
    CAST(stats.fg_pct AS FLOAT64) AS fg_pct,
    CAST(stats.fg3_pct AS FLOAT64) AS fg3_pct,
    CAST(stats.fg2_pct AS FLOAT64) AS fg2_pct,
    CAST(stats.efg_pct AS FLOAT64) AS efg_pct,
    CAST(stats.gp AS INT64) AS games_played
FROM source_data
