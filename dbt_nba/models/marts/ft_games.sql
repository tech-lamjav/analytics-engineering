{{
  config(
    description='NBA games for analysis',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

SELECT g.*,
    gth.is_b2b_game AS home_team_is_b2b_game,
    gtv.is_b2b_game AS visitor_team_is_b2b_game,
    gth.is_next_game AS home_team_is_next_game,
    gtv.is_next_game AS visitor_team_is_next_game,
FROM {{ ref('stg_games') }} g
LEFT JOIN {{ ref('int_games_teams_pilled') }} gth ON g.game_id = gth.game_id AND g.home_team_id = gth.team_id
LEFT JOIN {{ ref('int_games_teams_pilled') }} gtv ON g.game_id = gtv.game_id AND g.visitor_team_id = gtv.team_id