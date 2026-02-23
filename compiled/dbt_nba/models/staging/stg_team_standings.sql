

WITH source_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`raw_team_standings`
),

cleaned_data AS (
    SELECT
        team.id AS team_id,
        team.full_name AS team_name,
        team.abbreviation AS team_abbreviation,
        team.conference,
        team.city AS team_city,
        season,
        conference_rank,
        CAST(wins AS INT64) AS wins,
        CAST(losses AS INT64) AS losses,
        
        -- Calculate if current date is in DST period (second Sunday of March to first Sunday of November)
        -- DST: During DST, US cities advance 1 hour (except Arizona/Phoenix)
        CASE
            WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE  -- April to October
            WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN  -- March: check if after second Sunday
                CASE
                    WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                    ELSE FALSE
                END
            WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN  -- November: check if before first Sunday
                CASE
                    WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                    ELSE FALSE
                END
            ELSE FALSE
        END AS is_dst,
        
        -- Calculate injury report time offset (hours to add to 13:30 local to get Brasília time)
        -- Injury report releases at 13:30 local time
        CASE team.city
            -- Pacific Time (PT): -8 UTC standard, -7 UTC DST | Brasil -3 UTC
            WHEN 'Los Angeles' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 4 ELSE 5 END
            WHEN 'LA' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 4 ELSE 5 END
            WHEN 'Golden State' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 4 ELSE 5 END
            WHEN 'Portland' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 4 ELSE 5 END
            WHEN 'Sacramento' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 4 ELSE 5 END
            
            -- Mountain Time (MT): -7 UTC standard, -6 UTC DST | Brasil -3 UTC
            WHEN 'Denver' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 3 ELSE 4 END
            WHEN 'Utah' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 3 ELSE 4 END
            WHEN 'Oklahoma City' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 3 ELSE 4 END
            
            -- Mountain Time - No DST (Arizona): Always -7 UTC | Brasil -3 UTC
            WHEN 'Phoenix' THEN 4  -- Arizona does not observe DST
            
            -- Central Time (CT): -6 UTC standard, -5 UTC DST | Brasil -3 UTC
            WHEN 'Chicago' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'Dallas' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'Houston' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'Memphis' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'Minnesota' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'Milwaukee' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'New Orleans' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            WHEN 'San Antonio' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 2 ELSE 3 END
            
            -- Eastern Time (ET): -5 UTC standard, -4 UTC DST | Brasil -3 UTC
            WHEN 'Atlanta' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Boston' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Brooklyn' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Charlotte' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Cleveland' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Detroit' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Indiana' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Miami' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'New York' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Orlando' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Philadelphia' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Toronto' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
            WHEN 'Washington' THEN CASE WHEN (
                CASE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                            ELSE FALSE
                        END
                    WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                        CASE
                            WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                            ELSE FALSE
                        END
                    ELSE FALSE
                END
            ) THEN 1 ELSE 2 END
        END AS injury_report_time_offset_hours,
        
        -- Calculate injury report time in Brasília timezone (13:30 local + offset) as STRING
        FORMAT_TIME('%H:%M:%S', TIME_ADD(TIME(13, 0, 0), INTERVAL 
            CASE team.city
                -- Pacific Time (PT): -8 UTC standard, -7 UTC DST | Brasil -3 UTC
                WHEN 'Los Angeles' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 4 ELSE 5 END
                WHEN 'LA' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 4 ELSE 5 END
                WHEN 'Golden State' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 4 ELSE 5 END
                WHEN 'Portland' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 4 ELSE 5 END
                WHEN 'Sacramento' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 4 ELSE 5 END
                
                -- Mountain Time (MT): -7 UTC standard, -6 UTC DST | Brasil -3 UTC
                WHEN 'Denver' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 3 ELSE 4 END
                WHEN 'Utah' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 3 ELSE 4 END
                WHEN 'Oklahoma City' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 3 ELSE 4 END
                
                -- Mountain Time - No DST (Arizona): Always -7 UTC | Brasil -3 UTC
                WHEN 'Phoenix' THEN 4  -- Arizona does not observe DST
                
                -- Central Time (CT): -6 UTC standard, -5 UTC DST | Brasil -3 UTC
                WHEN 'Chicago' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'Dallas' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'Houston' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'Memphis' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'Minnesota' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'Milwaukee' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'New Orleans' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                WHEN 'San Antonio' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 2 ELSE 3 END
                
                -- Eastern Time (ET): -5 UTC standard, -4 UTC DST | Brasil -3 UTC
                WHEN 'Atlanta' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Boston' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Brooklyn' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Charlotte' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Cleveland' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Detroit' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Indiana' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Miami' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'New York' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Orlando' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Philadelphia' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Toronto' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
                WHEN 'Washington' THEN CASE WHEN (
                    CASE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) BETWEEN 4 AND 10 THEN TRUE
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 3 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) >= (8 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 3, 8)))) THEN TRUE
                                ELSE FALSE
                            END
                        WHEN EXTRACT(MONTH FROM CURRENT_DATE()) = 11 THEN
                            CASE
                                WHEN EXTRACT(DAY FROM CURRENT_DATE()) < (1 + (7 - EXTRACT(DAYOFWEEK FROM DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 11, 1)))) THEN TRUE
                                ELSE FALSE
                            END
                        ELSE FALSE
                    END
                ) THEN 1 ELSE 2 END
            END 
        HOUR)) AS team_injury_report_time_brasilia,
        
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
)

SELECT * FROM cleaned_data