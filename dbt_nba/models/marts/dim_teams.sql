{{
  config(
    description='NBA teams for analysis',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH team_rating AS (
    SELECT
        team_id,
        team_offensive_rating,
        team_defensive_rating,
        team_offensive_rating - team_defensive_rating AS net_rating,
        ROW_NUMBER() OVER (ORDER BY (team_offensive_rating - team_defensive_rating) DESC) AS team_rating_rank,
        ROW_NUMBER() OVER (ORDER BY team_offensive_rating DESC) AS team_offensive_rating_rank,
        ROW_NUMBER() OVER (ORDER BY team_defensive_rating DESC) AS team_defensive_rating_rank
    FROM (
        SELECT
            ap.team_id,
            AVG(sga.offensive_rating) AS team_offensive_rating,
            AVG(sga.defensive_rating) AS team_defensive_rating
        FROM {{ ref('stg_season_averages_general_advanced') }} AS sga
        INNER JOIN {{ ref('stg_active_players') }} AS ap ON sga.player_id = ap.player_id
        GROUP BY ap.team_id
    )
),

-- Aggregate team last five games (one row per team)
team_last_five AS (
    SELECT
        team_id,
        ANY_VALUE(team_last_five_games) AS team_last_five_games
    FROM {{ ref('int_games_teams_pilled') }}
    GROUP BY team_id
),

-- Get next game for each team (one row per team - the closest future game)
next_game_info AS (
    SELECT
        team_id,
        home_team_id,
        home_team_name,
        home_team_abbreviation,
        visitor_team_id,
        visitor_team_name,
        visitor_team_abbreviation,
        -- Determine if next game is at home
        CASE 
            WHEN team_id = home_team_id THEN TRUE
            ELSE FALSE
        END AS is_next_game_home
    FROM {{ ref('int_games_teams_pilled') }}
    WHERE is_next_game = true
    QUALIFY ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY game_date ASC, game_id ASC) = 1
),

-- Calculate next opponent info (one row per team)
next_opponent_info AS (
    SELECT
        ngi.team_id,
        ngi.is_next_game_home,
        CASE
            WHEN ngi.team_id = ngi.home_team_id THEN ngi.visitor_team_id
            WHEN ngi.team_id = ngi.visitor_team_id THEN ngi.home_team_id
        END AS next_opponent_id,
        CASE
            WHEN ngi.team_id = ngi.home_team_id THEN ngi.visitor_team_name
            WHEN ngi.team_id = ngi.visitor_team_id THEN ngi.home_team_name
        END AS next_opponent_name,
        CASE
            WHEN ngi.team_id = ngi.home_team_id THEN ngi.visitor_team_abbreviation
            WHEN ngi.team_id = ngi.visitor_team_id THEN ngi.home_team_abbreviation
        END AS next_opponent_abbreviation
    FROM next_game_info AS ngi
),

dim_teams AS (
    SELECT
        t.team_id,
        t.team_name,
        t.team_abbreviation,
        t.conference,
        t.team_city,
        t.season,
        t.conference_rank,
        t.wins,
        t.losses,
        tlf.team_last_five_games,
        tr.team_rating_rank,
        tr.team_offensive_rating_rank,
        tr.team_defensive_rating_rank,
        noi.next_opponent_id,
        noi.next_opponent_name,
        noi.next_opponent_abbreviation,
        noi.is_next_game_home,
        tlf_opp.team_last_five_games AS next_opponent_team_last_five_games,
        ts_opp.conference_rank AS next_opponent_conference_rank,
        tr_opp.team_rating_rank AS next_opponent_team_rating_rank,
        tr_opp.team_offensive_rating_rank AS next_opponent_team_offensive_rating_rank,
        tr_opp.team_defensive_rating_rank AS next_opponent_team_defensive_rating_rank,
        
        -- Injury report time for the team's home city (STRING type, from staging)
        t.team_injury_report_time_brasilia,
        
        -- Injury report time for the next game (STRING type, based on where the game is played)
        CASE 
            WHEN noi.is_next_game_home THEN t.team_injury_report_time_brasilia
            ELSE ts_opp.team_injury_report_time_brasilia
        END AS next_game_injury_report_time_brasilia,
        
        CURRENT_TIMESTAMP() AS loaded_at
    FROM {{ ref('stg_team_standings') }} AS t
    LEFT JOIN team_last_five AS tlf ON t.team_id = tlf.team_id
    LEFT JOIN team_rating AS tr ON t.team_id = tr.team_id
    LEFT JOIN next_opponent_info AS noi ON t.team_id = noi.team_id
    -- Next opponent data
    LEFT JOIN team_last_five AS tlf_opp ON noi.next_opponent_id = tlf_opp.team_id
    LEFT JOIN {{ ref('stg_team_standings') }} AS ts_opp ON noi.next_opponent_id = ts_opp.team_id
    LEFT JOIN team_rating AS tr_opp ON noi.next_opponent_id = tr_opp.team_id
)

SELECT * FROM dim_teams