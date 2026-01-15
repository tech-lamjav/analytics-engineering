{{
  config(
    description='NBA prop player analysis',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH

-- Performance of backup players when specific leaders are injured
backup_performance_when_leader_injured AS (
    SELECT
        ipr.player_id AS injured_leader_id,
        ipr.team_id,
        gps.stat_type,
        backup_player.player_id AS backup_player_id,
        AVG(backup_player.stat_value) AS backup_stats_when_leader_out
    FROM {{ ref('int_game_player_stats_not_played') }} AS ipr
    INNER JOIN {{ ref('int_game_player_stats_pilled') }} AS gps
        ON
            ipr.player_id = gps.player_id
            AND ipr.team_id = gps.team_id
    INNER JOIN {{ ref('int_game_player_stats_pilled') }} AS backup_player
        ON
            ipr.team_id = backup_player.team_id
            AND gps.game_id = backup_player.game_id
            AND gps.stat_type = backup_player.stat_type
            AND ipr.player_id != backup_player.player_id
    GROUP BY
        ipr.player_id,
        ipr.team_id,
        gps.stat_type,
        backup_player.player_id
),

-- Normal performance of backup players (all games, not just when no leader is injured)
backup_performance_normal AS (
    SELECT
        s.player_id,
        p.team_id,
        s.stat_type,
        s.stat_value AS backup_stats_normal
    FROM {{ ref('int_season_averages_general_base') }} AS s
    LEFT JOIN {{ ref('stg_active_players') }} AS p
        ON s.player_id = p.player_id
),

-- Base player statistics with odds and rankings
player_base_stats AS (
    SELECT
        p.player_id,
        p.team_id,
        s.stat_type,
        s.stat_value,
        ROW_NUMBER() OVER (
            PARTITION BY p.team_id, s.stat_type
            ORDER BY s.stat_value DESC
        ) AS stat_rank,
        AVG(s.stat_value) OVER (PARTITION BY p.team_id, s.stat_type) AS team_avg_stat,
        STDDEV(s.stat_value) OVER (PARTITION BY p.team_id, s.stat_type) AS team_stddev_stat
    FROM {{ ref('stg_active_players') }} AS p
    LEFT JOIN {{ ref('int_season_averages_general_base') }} AS s
        ON p.player_id = s.player_id
),

-- Calculate z-scores and ratings
player_ratings AS (
    SELECT
        *,
        CASE
            WHEN team_stddev_stat IS null OR team_stddev_stat = 0 THEN 0
            ELSE (stat_value - team_avg_stat) / team_stddev_stat
        END AS zscore,
        CASE
            WHEN (stat_value - team_avg_stat) / NULLIF(team_stddev_stat, 0) > 1.67 THEN 3
            WHEN (stat_value - team_avg_stat) / NULLIF(team_stddev_stat, 0) >= 1 THEN 2
            WHEN (stat_value - team_avg_stat) / NULLIF(team_stddev_stat, 0) >= 0 THEN 1
            ELSE 0
        END AS rating_stars
    FROM player_base_stats
),

-- Add injury status information
players_with_injury_status AS (
    SELECT
        pr.*,
        ir.status,
        COALESCE(pr.stat_rank = 1 AND ir.status IS NOT null, false) AS is_leader_with_injury,
        COALESCE(pr.stat_rank > 1, false OR ir.status IS null, false) AS is_available_backup
    FROM player_ratings AS pr
    LEFT JOIN {{ ref('stg_player_injuries') }} AS ir
        ON pr.player_id = ir.player_id
),

-- Identify next available players for each stat (always show next best player)
next_available_players AS (
    SELECT
        leader.team_id,
        leader.stat_type,
        leader.player_id AS current_leader_id,
        backup.player_id AS next_available_player_id,
        p.player_name AS next_available_player_name,
        COALESCE(bpwi.backup_stats_when_leader_out, 0) AS next_player_stats_when_leader_out,
        COALESCE(bpn.backup_stats_normal, 0) AS next_player_stats_normal
    FROM players_with_injury_status AS leader
    LEFT JOIN players_with_injury_status AS backup
        ON
            leader.team_id = backup.team_id
            AND leader.stat_type = backup.stat_type
            AND backup.is_available_backup = true
    LEFT JOIN {{ ref('stg_active_players') }} AS p
        ON backup.player_id = p.player_id
    LEFT JOIN backup_performance_when_leader_injured AS bpwi
        ON
            leader.player_id = bpwi.injured_leader_id
            AND leader.team_id = bpwi.team_id
            AND leader.stat_type = bpwi.stat_type
            AND backup.player_id = bpwi.backup_player_id
    LEFT JOIN backup_performance_normal AS bpn
        ON
            backup.team_id = bpn.team_id
            AND backup.player_id = bpn.player_id
            AND backup.stat_type = bpn.stat_type
    WHERE leader.is_leader_with_injury = true -- Always show next player for the current leader
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY leader.team_id, leader.stat_type
        ORDER BY backup.stat_rank
    ) = 1
)

-- Final result combining all data
-- Shows next available player info with conditional logic for injury-related stats
SELECT
    player_id,
    team_id,
    stat_type,
    rating_stars,
    is_leader_with_injury,
    is_available_backup,
    stat_rank,
    next_available_player_name,
    next_player_stats_when_leader_out,
    next_player_stats_normal,
    CURRENT_TIMESTAMP() AS loaded_at
FROM (
    SELECT
        pwis.*,
        -- Always show next available player name and normal stats
        nap.next_available_player_name,
        nap.next_player_stats_normal,
        -- Only show leader_out stats when current player is a leader with injury
        CASE
            WHEN pwis.is_leader_with_injury = true THEN nap.next_player_stats_when_leader_out
        END AS next_player_stats_when_leader_out
    FROM players_with_injury_status AS pwis
    LEFT JOIN next_available_players AS nap
        ON
            pwis.team_id = nap.team_id
            AND pwis.stat_type = nap.stat_type
)
ORDER BY player_id, stat_type