{{ config(
    description='Staging view for NBA team season averages tracking defense. Rim protection stats (def_rim_fg_pct, def_rim_fga) from Balldontlie API.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_team_season_averages_tracking_defense') }}
    WHERE season_type = 'regular'
)

SELECT
    CAST(team.id AS INT64) AS team_id,
    CAST(season AS INT64) AS season,
    season_type,
    CAST(stats.def_rim_fga AS FLOAT64) AS def_rim_fga,
    CAST(stats.def_rim_fgm AS FLOAT64) AS def_rim_fgm,
    CAST(stats.def_rim_fg_pct AS FLOAT64) AS def_rim_fg_pct,
    CAST(stats.dreb AS FLOAT64) AS dreb,
    CAST(stats.stl AS FLOAT64) AS stl,
    CAST(stats.blk AS FLOAT64) AS blk,
    CAST(stats.gp AS INT64) AS games_played
FROM source_data
