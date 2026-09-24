

WITH passing AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`stg_season_averages_tracking_passing`
),

players AS (
    SELECT
        player_id,
        player_name,
        position,
        team_id
    FROM `smartbetting-dados`.`nba`.`stg_active_players`
),

enriched AS (
    SELECT
        p.player_id,
        p.player_name,
        p.position,
        p.team_id,
        pa.season,
        pa.games_played,
        pa.minutes,
        pa.ast,
        pa.potential_ast,
        pa.passes_made,
        pa.passes_received,
        pa.secondary_ast,
        pa.ft_ast,
        pa.ast_points_created,
        pa.ast_adj,
        pa.ast_to_pass_pct,
        pa.ast_to_pass_pct_adj,
        SAFE_DIVIDE(pa.potential_ast, pa.passes_made) AS potential_ast_per_pass,
        SAFE_DIVIDE(pa.ast, pa.potential_ast) AS ast_conversion_rate,
    FROM passing AS pa
    INNER JOIN players AS p ON pa.player_id = p.player_id
)

SELECT
    player_id,
    player_name,
    position,
    team_id,
    season,
    games_played,
    minutes,
    ast,
    potential_ast,
    RANK() OVER (ORDER BY potential_ast DESC) AS potential_ast_rank,
    passes_made,
    passes_received,
    secondary_ast,
    ft_ast,
    ast_points_created,
    ast_adj,
    ast_to_pass_pct,
    ast_to_pass_pct_adj,
    potential_ast_per_pass,
    ast_conversion_rate,
    CURRENT_TIMESTAMP() AS loaded_at
FROM enriched
ORDER BY potential_ast DESC