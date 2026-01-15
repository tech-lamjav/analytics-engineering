{{
  config(
    description='NBA players for analysis',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH dim_players AS (

    SELECT
        p.player_id,
        p.player_name,
        p.position,
        p.team_id,
        p.team_name,
        p.team_abbreviation,
        s.age,
        g.last_game_text,
        ir.status,
        ir.description,
        ir.return_date,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM
        {{ ref('stg_active_players') }} AS p
    LEFT JOIN
        {{ ref('stg_season_averages_general_base') }} AS s
        ON p.player_id = s.player_id
    LEFT JOIN {{ ref('int_game_player_stats_last_game_text') }} AS g ON p.player_id = g.player_id
    LEFT JOIN {{ ref('stg_player_injuries') }} AS ir
        ON p.player_id = ir.player_id
)

SELECT * FROM dim_players