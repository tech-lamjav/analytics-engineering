

WITH source_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`raw_season_averages_tracking_passing`
    WHERE season_type = 'regular'
),

cleaned_data AS (
    SELECT
        CAST(player.id AS INT64) AS player_id,
        CAST(season AS INT64) AS season,
        season_type,
        CAST(stats.gp AS INT64) AS games_played,
        CAST(stats.min AS FLOAT64) AS minutes,
        CAST(stats.ast AS FLOAT64) AS ast,
        CAST(stats.potential_ast AS FLOAT64) AS potential_ast,
        CAST(stats.passes_made AS FLOAT64) AS passes_made,
        CAST(stats.passes_received AS FLOAT64) AS passes_received,
        CAST(stats.secondary_ast AS FLOAT64) AS secondary_ast,
        CAST(stats.ft_ast AS FLOAT64) AS ft_ast,
        CAST(stats.ast_points_created AS FLOAT64) AS ast_points_created,
        CAST(stats.ast_adj AS FLOAT64) AS ast_adj,
        CAST(stats.ast_to_pass_pct AS FLOAT64) AS ast_to_pass_pct,
        CAST(stats.ast_to_pass_pct_adj AS FLOAT64) AS ast_to_pass_pct_adj,
    FROM source_data
)

SELECT * FROM cleaned_data