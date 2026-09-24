

WITH triggers AS (
    SELECT DISTINCT
        trigger_player_id,
        trigger_name,
        trigger_team_id,
        trigger_team_abbr,
        trigger_status
    FROM `smartbetting-dados`.`nba`.`int_daily_triggers`
),

trigger_team_season_games AS (
    SELECT
        tr.trigger_player_id,
        tr.trigger_team_id,
        tg.game_id,
        tg.game_date
    FROM triggers tr
    INNER JOIN `smartbetting-dados`.`nba`.`int_games_teams_pilled` tg
        ON tg.team_id = tr.trigger_team_id
    WHERE
        tg.game_date >= '2025-10-01'
        AND tg.game_date < CURRENT_DATE()
        AND tg.win_loss IS NOT NULL
),

trigger_played_games AS (
    SELECT DISTINCT
        p.player_id AS trigger_player_id,
        p.game_id,
        p.game_date
    FROM `smartbetting-dados`.`nba`.`int_game_player_stats_pilled` p
    WHERE p.stat_type = 'player_points'
),

sem_dates AS (
    SELECT
        tsg.trigger_player_id,
        tsg.game_date
    FROM trigger_team_season_games tsg
    WHERE NOT EXISTS (
        SELECT 1
        FROM trigger_played_games tpg
        WHERE
            tpg.trigger_player_id = tsg.trigger_player_id
            AND tpg.game_id = tsg.game_id
    )
),

com_dates AS (
    SELECT
        tsg.trigger_player_id,
        tsg.game_date
    FROM trigger_team_season_games tsg
    WHERE EXISTS (
        SELECT 1
        FROM trigger_played_games tpg
        WHERE
            tpg.trigger_player_id = tsg.trigger_player_id
            AND tpg.game_id = tsg.game_id
    )
),

teammates AS (
    SELECT DISTINCT
        tr.trigger_player_id,
        tr.trigger_team_id,
        dp.player_id AS teammate_player_id,
        dp.player_name AS teammate_name,
        dp.position AS teammate_position
    FROM triggers tr
    INNER JOIN `smartbetting-dados`.`nba`.`dim_players` dp
        ON dp.team_id = tr.trigger_team_id
        AND dp.player_id != tr.trigger_player_id
),

teammate_minutes AS (
    SELECT
        tm.trigger_player_id,
        tm.teammate_player_id,
        AVG(m.stat_value) AS teammate_avg_minutes
    FROM teammates tm
    INNER JOIN `smartbetting-dados`.`nba`.`int_games_teams_pilled` tg
        ON tg.team_id = tm.trigger_team_id
        AND tg.game_date >= '2025-10-01'
        AND tg.game_date < CURRENT_DATE()
        AND tg.win_loss IS NOT NULL
    INNER JOIN `smartbetting-dados`.`nba`.`int_game_player_stats_pilled` m
        ON m.player_id = tm.teammate_player_id
        AND m.team_id = tm.trigger_team_id
        AND m.game_id = tg.game_id
        AND m.stat_type = 'player_minutes'
    GROUP BY tm.trigger_player_id, tm.teammate_player_id
),

stats_sem AS (
    SELECT
        tm.trigger_player_id,
        tm.teammate_player_id,
        tm.teammate_name,
        s.stat_type,
        AVG(s.stat_value) AS avg_sem,
        STDDEV(s.stat_value) AS stddev_sem,
        COUNT(*) AS jogos_sem
    FROM teammates tm
    INNER JOIN `smartbetting-dados`.`nba`.`int_game_player_stats_pilled` s
        ON s.player_id = tm.teammate_player_id
        AND s.team_id = tm.trigger_team_id
    INNER JOIN sem_dates sd
        ON sd.trigger_player_id = tm.trigger_player_id
        AND sd.game_date = s.game_date
    WHERE s.stat_type IN (
        'player_points',
        'player_rebounds',
        'player_assists'
    )
    GROUP BY tm.trigger_player_id, tm.teammate_player_id, tm.teammate_name, s.stat_type
),

stats_com AS (
    SELECT
        tm.trigger_player_id,
        tm.teammate_player_id,
        tm.teammate_name,
        s.stat_type,
        AVG(s.stat_value) AS avg_com,
        COUNT(*) AS jogos_com
    FROM teammates tm
    INNER JOIN `smartbetting-dados`.`nba`.`int_game_player_stats_pilled` s
        ON s.player_id = tm.teammate_player_id
        AND s.team_id = tm.trigger_team_id
    INNER JOIN com_dates cd
        ON cd.trigger_player_id = tm.trigger_player_id
        AND cd.game_date = s.game_date
    WHERE s.stat_type IN (
        'player_points',
        'player_rebounds',
        'player_assists'
    )
    GROUP BY tm.trigger_player_id, tm.teammate_player_id, tm.teammate_name, s.stat_type
),

analysis_360 AS (
    SELECT
        sem.trigger_player_id,
        sem.teammate_player_id,
        sem.teammate_name,
        sem.stat_type,
        com.avg_com,
        sem.avg_sem,
        sem.stddev_sem,
        (sem.avg_sem - com.avg_com) AS gap,
        SAFE_DIVIDE((sem.avg_sem - com.avg_com), NULLIF(com.avg_com, 0)) * 100 AS gap_pct,
        com.jogos_com,
        sem.jogos_sem
    FROM stats_sem sem
    INNER JOIN stats_com com
        ON sem.trigger_player_id = com.trigger_player_id
        AND sem.teammate_player_id = com.teammate_player_id
        AND sem.stat_type = com.stat_type
    WHERE sem.jogos_sem >= 5
)

SELECT
    t.trigger_player_id,
    t.trigger_name,
    t.trigger_team_id,
    t.trigger_team_abbr,
    LOWER(t.trigger_status) AS trigger_status,
    a.teammate_player_id,
    tm.teammate_name,
    tm.teammate_position,
    a.stat_type,
    a.avg_com,
    a.avg_sem,
    a.stddev_sem,
    a.gap,
    a.gap_pct,
    a.jogos_com,
    a.jogos_sem,
    m.teammate_avg_minutes,
    CURRENT_TIMESTAMP() AS loaded_at
FROM analysis_360 a
INNER JOIN triggers t
    ON a.trigger_player_id = t.trigger_player_id
INNER JOIN teammates tm
    ON tm.trigger_player_id = a.trigger_player_id
    AND tm.teammate_player_id = a.teammate_player_id
INNER JOIN teammate_minutes m
    ON m.trigger_player_id = a.trigger_player_id
    AND m.teammate_player_id = a.teammate_player_id
WHERE m.teammate_avg_minutes >= 15