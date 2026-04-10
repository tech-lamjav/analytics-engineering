{{ config(
    description='Stage 3/3C: 360 COM vs SEM teammate stats, line crossing, and signal strength per daily trigger'
) }}

WITH trigger_team_season_games AS (
    SELECT
        tr.trigger_player_id,
        tr.trigger_team_id,
        tg.game_id,
        tg.game_date
    FROM {{ ref('int_daily_triggers') }} tr
    INNER JOIN {{ ref('int_games_teams_pilled') }} tg
        ON tg.team_id = tr.trigger_team_id
    WHERE
        tg.game_date >= '2025-10-01'
        AND tg.game_date < CURRENT_DATE('America/Sao_Paulo')
        AND tg.win_loss IS NOT NULL
),

trigger_played_games AS (
    SELECT DISTINCT
        p.player_id AS trigger_player_id,
        p.game_id,
        p.game_date
    FROM {{ ref('int_game_player_stats_pilled') }} p
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
        dp.player_id AS backup_player_id,
        dp.player_name AS backup_player_name
    FROM {{ ref('int_daily_triggers') }} tr
    INNER JOIN {{ ref('dim_players') }} dp
        ON dp.team_id = tr.trigger_team_id
        AND dp.player_id != tr.trigger_player_id
        AND dp.status IS NULL
),

stats_sem AS (
    SELECT
        tm.trigger_player_id,
        tm.backup_player_id,
        tm.backup_player_name,
        s.stat_type,
        AVG(s.stat_value) AS avg_sem,
        STDDEV(s.stat_value) AS stddev_sem,
        COUNT(*) AS jogos_sem
    FROM teammates tm
    INNER JOIN {{ ref('int_game_player_stats_pilled') }} s
        ON s.player_id = tm.backup_player_id
        AND s.team_id = tm.trigger_team_id
    INNER JOIN sem_dates sd
        ON sd.trigger_player_id = tm.trigger_player_id
        AND sd.game_date = s.game_date
    WHERE s.stat_type IN (
        'player_points',
        'player_rebounds',
        'player_assists',
        'player_minutes',
        'player_points_rebounds_assists'
    )
    GROUP BY tm.trigger_player_id, tm.backup_player_id, tm.backup_player_name, s.stat_type
),

stats_com AS (
    SELECT
        tm.trigger_player_id,
        tm.backup_player_id,
        tm.backup_player_name,
        s.stat_type,
        AVG(s.stat_value) AS avg_com,
        COUNT(*) AS jogos_com
    FROM teammates tm
    INNER JOIN {{ ref('int_game_player_stats_pilled') }} s
        ON s.player_id = tm.backup_player_id
        AND s.team_id = tm.trigger_team_id
    INNER JOIN com_dates cd
        ON cd.trigger_player_id = tm.trigger_player_id
        AND cd.game_date = s.game_date
    WHERE s.stat_type IN (
        'player_points',
        'player_rebounds',
        'player_assists',
        'player_minutes',
        'player_points_rebounds_assists'
    )
    GROUP BY tm.trigger_player_id, tm.backup_player_id, tm.backup_player_name, s.stat_type
),

analysis_360 AS (
    SELECT
        sem.trigger_player_id,
        sem.backup_player_id,
        sem.backup_player_name,
        sem.stat_type,
        com.avg_com,
        sem.avg_sem,
        sem.stddev_sem,
        SAFE_DIVIDE(sem.stddev_sem, NULLIF(sem.avg_sem, 0)) * 100 AS cv_sem,
        (sem.avg_sem - com.avg_com) AS gap,
        SAFE_DIVIDE((sem.avg_sem - com.avg_com), NULLIF(com.avg_com, 0)) * 100 AS gap_pct,
        com.jogos_com,
        sem.jogos_sem
    FROM stats_sem sem
    INNER JOIN stats_com com
        ON sem.trigger_player_id = com.trigger_player_id
        AND sem.backup_player_id = com.backup_player_id
        AND sem.stat_type = com.stat_type
    WHERE
        sem.jogos_sem >= 3
        AND (sem.avg_sem - com.avg_com) > 0.5
),

ranked_stats AS (
    SELECT
        a.*,
        ROW_NUMBER() OVER (
            PARTITION BY a.trigger_player_id, a.backup_player_id
            ORDER BY a.gap_pct DESC
        ) AS stat_rank_in_backup
    FROM analysis_360 a
),

top_2_stats AS (
    SELECT * FROM ranked_stats
    WHERE stat_rank_in_backup <= 2
),

most_recent_line AS (
    SELECT
        player_id,
        stat_type,
        ANY_VALUE(line_value_most_recent) AS line_value_most_recent
    FROM {{ ref('ft_game_player_stats') }}
    WHERE line_value_most_recent IS NOT NULL
    GROUP BY player_id, stat_type
),

with_lines AS (
    SELECT
        t2.*,
        mrl.line_value_most_recent AS line_value
    FROM top_2_stats t2
    LEFT JOIN most_recent_line mrl
        ON t2.backup_player_id = mrl.player_id
        AND t2.stat_type = mrl.stat_type
),

gap_metrics AS (
    SELECT
        wl.*,
        (wl.avg_sem - wl.line_value) AS gap_vs_line,
        SAFE_DIVIDE((wl.avg_sem - wl.line_value), NULLIF(wl.line_value, 0)) * 100 AS gap_vs_line_pct
    FROM with_lines wl
),

with_signals AS (
    SELECT
        gm.*,
        CASE
            WHEN gm.gap_vs_line_pct IS NOT NULL THEN CASE
                WHEN gm.gap_vs_line_pct > 15 AND gm.jogos_sem >= 5 THEN 'FORTE'
                WHEN gm.gap_vs_line_pct > 10 OR (gm.gap_vs_line_pct > 5 AND gm.jogos_sem >= 10) THEN 'MEDIO'
                WHEN gm.gap_vs_line_pct > 5 AND gm.jogos_sem >= 3 THEN 'FRACO'
            END
            ELSE CASE
                WHEN gm.gap_pct > 15 AND gm.jogos_sem >= 5 THEN 'FORTE'
                WHEN gm.gap_pct > 10 OR (gm.gap_pct > 5 AND gm.jogos_sem >= 10) THEN 'MEDIO'
                WHEN gm.gap_pct > 5 AND gm.jogos_sem >= 3 THEN 'FRACO'
            END
        END AS signal
    FROM gap_metrics gm
)

SELECT
    dt.game_id,
    dt.game_date,
    dt.game_time_brasilia,
    dt.home_team_abbr,
    dt.visitor_team_abbr,
    dt.trigger_player_id,
    dt.trigger_name,
    dt.trigger_status,
    dt.trigger_team_id,
    dt.trigger_team_abbr,
    dt.trigger_days_out,
    dt.trigger_freshness,
    dt.trigger_participation_pct,
    dt.is_b2b,
    dt.fatigue_level,
    dt.is_home,
    ws.backup_player_id,
    ws.backup_player_name,
    ws.stat_type,
    ws.avg_com,
    ws.avg_sem,
    ws.stddev_sem,
    ws.cv_sem,
    ws.gap,
    ws.gap_pct,
    ws.jogos_com,
    ws.jogos_sem,
    ws.line_value,
    ws.gap_vs_line,
    ws.gap_vs_line_pct,
    ws.signal,
    CURRENT_TIMESTAMP() AS loaded_at
FROM with_signals ws
INNER JOIN {{ ref('int_daily_triggers') }} dt
    ON ws.trigger_player_id = dt.trigger_player_id