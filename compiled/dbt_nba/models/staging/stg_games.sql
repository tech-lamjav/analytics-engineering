

WITH source_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`raw_games`
),

-- Unnest the games array to get individual games
unnested_games AS (
    SELECT
        season,
        date,
        total_games,
        game
    FROM source_data,
    UNNEST(games) AS game
),

cleaned_data AS (
    SELECT
        CAST(game.id AS INT64) AS game_id,
        CAST(season AS INT64) AS season,
        PARSE_DATE('%Y-%m-%d', date) AS game_date,
        --game.status AS game_status,
        --CAST(game.period AS INT64) AS period,
        --game.time,
        --CAST(game.postseason AS BOOL) AS is_postseason,
        game.datetime AS game_datetime_utc,
        -- Convert datetime to Brasília timezone (UTC-3)
        -- Use PARSE_TIMESTAMP for timezone support, then convert to DATETIME
        CASE
            WHEN game.datetime IS NOT NULL
            THEN DATETIME(DATETIME_ADD(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', game.datetime), INTERVAL -3 HOUR))
        END AS game_datetime_brasilia,
        --game.ist_stage,

        -- Home team information
        CAST(game.home_team.id AS INT64) AS home_team_id,
        --game.home_team.conference AS home_team_conference,
        --game.home_team.division AS home_team_division,
        --game.home_team.city AS home_team_city,
        --game.home_team.name AS home_team_name,
        game.home_team.full_name AS home_team_name,
        game.home_team.abbreviation AS home_team_abbreviation,
        CAST(game.home_team_score AS INT64) AS home_team_score,

        -- Visitor team information
        CAST(game.visitor_team.id AS INT64) AS visitor_team_id,
        --game.visitor_team.conference AS visitor_team_conference,
        --game.visitor_team.division AS visitor_team_division,
        --game.visitor_team.city AS visitor_team_city,
        --game.visitor_team.name AS visitor_team_name,
        game.visitor_team.full_name AS visitor_team_name,
        game.visitor_team.abbreviation AS visitor_team_abbreviation,
        CAST(game.visitor_team_score AS INT64) AS visitor_team_score,

        -- Quarter scores (home)
        --CAST(game.home_q1 AS INT64) AS home_q1,
        --CAST(game.home_q2 AS INT64) AS home_q2,
        --CAST(game.home_q3 AS INT64) AS home_q3,
        --CAST(game.home_q4 AS INT64) AS home_q4,
        --CAST(game.home_ot1 AS INT64) AS home_ot1,
        --CAST(game.home_ot2 AS INT64) AS home_ot2,
        --CAST(game.home_ot3 AS INT64) AS home_ot3,
        --CAST(game.home_timeouts_remaining AS INT64) AS home_timeouts_remaining,
        --CAST(game.home_in_bonus AS BOOL) AS home_in_bonus,

        -- Quarter scores (visitor)
        --CAST(game.visitor_q1 AS INT64) AS visitor_q1,
        --CAST(game.visitor_q2 AS INT64) AS visitor_q2,
        --CAST(game.visitor_q3 AS INT64) AS visitor_q3,
        --CAST(game.visitor_q4 AS INT64) AS visitor_q4,
        --CAST(game.visitor_ot1 AS INT64) AS visitor_ot1,
        --CAST(game.visitor_ot2 AS INT64) AS visitor_ot2,
        --CAST(game.visitor_ot3 AS INT64) AS visitor_ot3,
        --CAST(game.visitor_timeouts_remaining AS INT64) AS visitor_timeouts_remaining,
        --CAST(game.visitor_in_bonus AS BOOL) AS visitor_in_bonus,

        -- Calculated fields
        CASE
            WHEN CAST(game.home_team_score AS INT64) > CAST(game.visitor_team_score AS INT64) 
            THEN CAST(game.home_team.id AS INT64)
            WHEN CAST(game.visitor_team_score AS INT64) > CAST(game.home_team_score AS INT64) 
            THEN CAST(game.visitor_team.id AS INT64)
        END AS winner_team_id,

        CURRENT_TIMESTAMP() AS loaded_at
    FROM unnested_games
)

SELECT * FROM cleaned_data