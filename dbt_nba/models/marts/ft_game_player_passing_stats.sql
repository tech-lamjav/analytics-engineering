{{
  config(
    description='NBA fact: passing/playmaking stats per player per game from /nba/v2/stats/advanced. Game-by-game series for trend analysis on assists props.',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH advanced AS (
    SELECT * FROM {{ ref('stg_game_player_advanced_stats') }}
    WHERE season = 2025
      AND period = 0  -- jogo completo (não quartos)
)

SELECT
    a.player_id,
    a.team_id,
    a.game_id,
    a.game_date,
    a.season,
    a.passes,
    a.secondary_assists,
    a.free_throw_assists,
    a.screen_assists,
    a.screen_assist_points,
    a.assist_percentage,
    a.assist_ratio,
    a.assist_to_turnover,
    a.turnover_ratio,
    a.usage_percentage,
    a.touches,
    a.possessions,
    SAFE_DIVIDE(a.secondary_assists + a.free_throw_assists, a.passes) AS extra_assists_per_pass,
    gt.is_b2b_game,
    CASE
        WHEN a.team_id = gt.home_team_id THEN gt.visitor_team_abbreviation
        WHEN a.team_id = gt.visitor_team_id THEN '@' || gt.home_team_abbreviation
    END AS played_against,
    CASE
        WHEN a.team_id = gt.home_team_id THEN 'Casa'
        WHEN a.team_id = gt.visitor_team_id THEN 'Fora'
    END AS home_away,
    CURRENT_TIMESTAMP() AS loaded_at
FROM advanced AS a
LEFT JOIN {{ ref('int_games_teams_pilled') }} AS gt
    ON a.game_id = gt.game_id
    AND a.team_id = gt.team_id
    AND gt.game_date <= CURRENT_DATE()
ORDER BY player_id, game_id
