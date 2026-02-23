

WITH base_data AS (
    SELECT 
        *,
        -- Ensure game_date is DATE type (safety conversion - handles both DATE and STRING)
        COALESCE(
            SAFE_CAST(game_date AS DATE),
            PARSE_DATE('%Y-%m-%d', CAST(game_date AS STRING))
        ) AS game_date_typed
    FROM `smartbetting-dados`.`nba`.`stg_games`
),

-- Create all team games to identify B2B patterns and next games
all_team_games AS (
    -- Home team games
    SELECT
        game_id,
        game_date_typed AS game_date,
        --game_status,
        home_team_id AS team_id,
        home_team_abbreviation AS team_abbreviation,
        home_team_name AS team_name,
        home_team_score AS team_score,
        CASE
            WHEN winner_team_id = home_team_id THEN 'V'
            WHEN winner_team_id = visitor_team_id THEN 'D'
        END AS win_loss,
        home_team_id,
        home_team_abbreviation,
        home_team_name,
        visitor_team_id,
        visitor_team_abbreviation,
        visitor_team_name
    FROM base_data

    UNION ALL

    -- Visitor team games
    SELECT
        game_id,
        game_date_typed AS game_date,
        --game_status,
        visitor_team_id AS team_id,
        visitor_team_abbreviation AS team_abbreviation,
        visitor_team_name AS team_name,
        visitor_team_score AS team_score,
        CASE
            WHEN winner_team_id = visitor_team_id THEN 'V'
            WHEN winner_team_id = home_team_id THEN 'D'
        END AS win_loss,
        home_team_id,
        home_team_abbreviation,
        home_team_name,
        visitor_team_id,
        visitor_team_abbreviation,
        visitor_team_name
    FROM base_data
),

-- Identify consecutive games for each team (only for games before 2025-04-07 for B2B analysis)
consecutive_games AS (
    SELECT
        game_id,
        team_id,
        LAG(game_date) OVER (PARTITION BY team_id ORDER BY game_date, game_id) AS previous_game_date,
        DATE_DIFF(game_date, LAG(game_date) OVER (PARTITION BY team_id ORDER BY game_date, game_id), DAY)
            AS days_between_games
    FROM all_team_games
),

-- Identify B2B games
b2b_games AS (
    SELECT DISTINCT
        game_id,
        team_id,
        true AS is_b2b_game
    FROM consecutive_games
    WHERE
        days_between_games = 1
        AND previous_game_date IS NOT null  -- Ensure there's a previous game
),

-- Identify next game for each team (starting from 2025-04-07)
next_games AS (
    SELECT DISTINCT
        game_id,
        team_id,
        true AS is_next_game
    FROM all_team_games
    WHERE
        game_date >= CURRENT_DATE()
        AND game_id IN (
            -- Get the first game for each team on or after 2025-04-07
            SELECT
                FIRST_VALUE(game_id) OVER (
                    PARTITION BY team_id
                    ORDER BY game_date ASC, game_id ASC
                ) AS first_game_id
            FROM all_team_games
            WHERE game_date >= CURRENT_DATE()
        )
),

-- Final result with B2B and next game flags

last_five_games AS (
    SELECT
        team_id,
        STRING_AGG(win_loss, ' ' ORDER BY game_date DESC, game_id DESC) AS team_last_five_games
    FROM (
        SELECT
            team_id,
            game_id,
            game_date,
            win_loss,
            ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY game_date DESC, game_id DESC) AS row_num
        FROM all_team_games
        WHERE 
            win_loss IS NOT NULL  -- Only completed games
            AND game_date < CURRENT_DATE()  -- Only past games
    )
    WHERE row_num <= 5
    GROUP BY team_id
),

final_result AS (
    SELECT
        atg.*,
        lfg.team_last_five_games,
        COALESCE(bb.is_b2b_game, false) AS is_b2b_game,
        COALESCE(ng.is_next_game, false) AS is_next_game,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM all_team_games AS atg
    LEFT JOIN b2b_games AS bb ON atg.game_id = bb.game_id AND atg.team_id = bb.team_id
    LEFT JOIN next_games AS ng ON atg.game_id = ng.game_id AND atg.team_id = ng.team_id
    LEFT JOIN last_five_games AS lfg ON atg.team_id = lfg.team_id
)

SELECT * FROM final_result