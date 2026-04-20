{{ config(
    description='Staging table for NBA team season averages (tracking/rebounding). Rebound chance percentages, contested rebound rates, and average rebound distances from Balldontlie API.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_tracking_rebounding') }}
    WHERE season_type = 'regular'
),

cleaned_data AS (
    SELECT
        CAST(team.id AS INT64) AS team_id,
        CAST(season AS INT64) AS season,
        season_type,
        CAST(stats.oreb_chance_pct AS FLOAT64) AS oreb_chance_pct,
        CAST(stats.dreb_chance_pct AS FLOAT64) AS dreb_chance_pct,
        CAST(stats.oreb_chance_pct_adj AS FLOAT64) AS oreb_chance_pct_adj,
        CAST(stats.dreb_chance_pct_adj AS FLOAT64) AS dreb_chance_pct_adj,
        CAST(stats.reb_chance_pct AS FLOAT64) AS reb_chance_pct,
        CAST(stats.oreb_chances AS FLOAT64) AS oreb_chances,
        CAST(stats.dreb_chances AS FLOAT64) AS dreb_chances,
        CAST(stats.reb_chances AS FLOAT64) AS reb_chances,
        CAST(stats.oreb_contest_pct AS FLOAT64) AS oreb_contest_pct,
        CAST(stats.dreb_contest_pct AS FLOAT64) AS dreb_contest_pct,
        CAST(stats.reb_contest_pct AS FLOAT64) AS reb_contest_pct,
        CAST(stats.oreb_uncontest AS FLOAT64) AS oreb_uncontest,
        CAST(stats.dreb_uncontest AS FLOAT64) AS dreb_uncontest,
        CAST(stats.avg_oreb_dist AS FLOAT64) AS avg_oreb_dist,
        CAST(stats.avg_dreb_dist AS FLOAT64) AS avg_dreb_dist,
        CAST(stats.avg_reb_dist AS FLOAT64) AS avg_reb_dist,
    FROM source_data
)

SELECT * FROM cleaned_data
