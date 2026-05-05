{{
  config(
    description='NBA player stats by quarter (1Q) and half (1H) per game',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH period_stats AS (
    SELECT * FROM {{ ref('stg_game_player_stats_period') }}
),

q1 AS (
    SELECT
        player_id,
        team_id,
        game_id,
        game_date,
        minutes         AS q1_minutes,
        points          AS q1_points,
        rebounds        AS q1_rebounds,
        assists         AS q1_assists
    FROM period_stats
    WHERE period = 1
),

first_half AS (
    SELECT
        player_id,
        team_id,
        game_id,
        game_date,
        SUM(points)   AS h1_points,
        SUM(rebounds) AS h1_rebounds,
        SUM(assists)  AS h1_assists
    FROM period_stats
    WHERE period IN (1, 2)
    GROUP BY player_id, team_id, game_id, game_date
)

SELECT
    q1.player_id,
    q1.game_date,
    q1.game_id,
    q1.q1_minutes,
    q1.q1_points,
    q1.q1_rebounds,
    q1.q1_assists,
    fh.h1_points,
    fh.h1_rebounds,
    fh.h1_assists,
    CASE
        WHEN q1.team_id = gt.home_team_id THEN gt.visitor_team_abbreviation
        WHEN q1.team_id = gt.visitor_team_id THEN '@' || gt.home_team_abbreviation
    END AS played_against,
    CASE
        WHEN q1.team_id = gt.home_team_id THEN 'Casa'
        WHEN q1.team_id = gt.visitor_team_id THEN 'Fora'
    END AS home_away,
    gt.is_b2b_game,
    CURRENT_TIMESTAMP() AS loaded_at
FROM q1
LEFT JOIN first_half AS fh
    ON q1.player_id = fh.player_id AND q1.game_id = fh.game_id
LEFT JOIN {{ ref('int_games_teams_pilled') }} AS gt
    ON q1.game_id = gt.game_id AND q1.team_id = gt.team_id AND gt.game_date <= CURRENT_DATE()
WHERE q1.q1_minutes > 0
ORDER BY q1.player_id, q1.game_id
