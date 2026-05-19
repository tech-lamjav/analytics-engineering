{{
  config(
    materialized='table',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

SELECT
    p.player_id,
    p.stat_type,
    p.line_value AS line_value_most_recent,
    CURRENT_TIMESTAMP() AS loaded_at
FROM {{ ref('stg_player_props') }} AS p
LEFT JOIN {{ ref('stg_games') }} AS g
    ON g.game_id = p.game_id
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.player_id, p.stat_type
    ORDER BY g.game_date DESC
) = 1
