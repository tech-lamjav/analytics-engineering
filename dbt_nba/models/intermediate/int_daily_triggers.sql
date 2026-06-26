{{ config(
    description='Daily injury triggers for games on today/tomorrow (Brasília) with fatigue (Stage 1) and market validation (Stage 2.5)'
) }}

WITH todays_games AS (
    SELECT DISTINCT
        g.game_id,
        g.game_date,
        g.game_datetime_brasilia,
        g.home_team_id,
        g.home_team_abbreviation,
        g.visitor_team_id,
        g.visitor_team_abbreviation
    FROM {{ ref('ft_games') }} g
    WHERE g.game_date BETWEEN CURRENT_DATE('America/Sao_Paulo')
                          AND DATE_ADD(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 DAY)
),

triggers_raw AS (
    SELECT
        tg.game_id,
        tg.game_date,
        tg.game_datetime_brasilia,
        tg.home_team_id,
        tg.home_team_abbreviation,
        tg.visitor_team_id,
        tg.visitor_team_abbreviation,
        p.player_id AS trigger_player_id,
        p.player_name AS trigger_name,
        p.status AS trigger_status,
        p.team_id AS trigger_team_id,
        p.team_abbreviation AS trigger_team_abbr,
        p.description AS trigger_description,
        gt.is_b2b_game,
        (p.team_id = tg.home_team_id) AS is_home
    FROM todays_games tg
    INNER JOIN {{ ref('dim_players') }} p
        ON p.team_id IN (tg.home_team_id, tg.visitor_team_id)
    LEFT JOIN {{ ref('int_games_teams_pilled') }} gt
        ON tg.game_id = gt.game_id AND p.team_id = gt.team_id
    WHERE p.status IN ('Out', 'Doubtful', 'Questionable')
),

trigger_last_played AS (
    SELECT
        player_id,
        MAX(game_date) AS last_played_date
    FROM {{ ref('int_game_player_stats_pilled') }}
    WHERE stat_type = 'player_points'
    GROUP BY player_id
),

trigger_games_played AS (
    -- Numerador escopado por time: jogos jogados PELO time atual do trigger.
    -- Sem team_id, jogadores trocados somariam jogos de times anteriores e o
    -- participation_pct podia passar de 1 e furar o gate >= 0.5.
    SELECT
        player_id,
        team_id,
        COUNT(DISTINCT game_id) AS jogos_trigger
    FROM {{ ref('int_game_player_stats_pilled') }}
    WHERE
        stat_type = 'player_points'
        AND game_date >= '{{ var('nba_season', 2025) }}-10-01'
        AND game_date < CURRENT_DATE('America/Sao_Paulo')
    GROUP BY player_id, team_id
),

team_games_count AS (
    SELECT
        team_id,
        COUNT(DISTINCT game_id) AS total_team_games
    FROM {{ ref('int_games_teams_pilled') }}
    WHERE
        game_date >= '{{ var('nba_season', 2025) }}-10-01'
        AND game_date < CURRENT_DATE('America/Sao_Paulo')
        AND win_loss IS NOT NULL
    GROUP BY team_id
),

joined AS (
    SELECT
        tr.*,
        tlp.last_played_date,
        DATE_DIFF(CURRENT_DATE('America/Sao_Paulo'), tlp.last_played_date, DAY) AS trigger_days_out,
        SAFE_DIVIDE(
            COALESCE(tgp.jogos_trigger, 0),
            NULLIF(tgc.total_team_games, 0)
        ) AS trigger_participation_pct
    FROM triggers_raw tr
    LEFT JOIN trigger_last_played tlp ON tr.trigger_player_id = tlp.player_id
    LEFT JOIN trigger_games_played tgp
        ON tr.trigger_player_id = tgp.player_id
        AND tr.trigger_team_id = tgp.team_id
    LEFT JOIN team_games_count tgc ON tr.trigger_team_id = tgc.team_id
),

fatigue AS (
    SELECT
        j.*,
        CASE
            WHEN j.is_b2b_game AND NOT j.is_home THEN 'ALTA'
            WHEN j.is_b2b_game AND j.is_home THEN 'MEDIA'
            ELSE 'BAIXA'
        END AS fatigue_level,
        CASE
            WHEN j.trigger_days_out IS NULL THEN NULL
            WHEN j.trigger_days_out BETWEEN 0 AND 3 THEN 'NOVA'
            WHEN j.trigger_days_out BETWEEN 4 AND 7 THEN 'RECENTE'
            WHEN j.trigger_days_out BETWEEN 8 AND 14 THEN 'EXTENDIDA'
            ELSE 'LONGO_PRAZO'
        END AS trigger_freshness_raw
    FROM joined j
)

SELECT
    game_id,
    game_date,
    game_datetime_brasilia,
    FORMAT_DATETIME('%H:%M', game_datetime_brasilia) AS game_time_brasilia,
    home_team_abbreviation AS home_team_abbr,
    visitor_team_abbreviation AS visitor_team_abbr,
    trigger_player_id,
    trigger_name,
    trigger_status,
    trigger_team_id,
    trigger_team_abbr,
    trigger_days_out,
    CASE trigger_freshness_raw
        WHEN 'LONGO_PRAZO' THEN NULL
        ELSE trigger_freshness_raw
    END AS trigger_freshness,
    trigger_participation_pct,
    COALESCE(is_b2b_game, FALSE) AS is_b2b,
    fatigue_level,
    is_home,
FROM fatigue
WHERE
    last_played_date IS NOT NULL
    AND trigger_days_out IS NOT NULL
    AND trigger_freshness_raw IS NOT NULL
    AND trigger_freshness_raw != 'LONGO_PRAZO'
    AND COALESCE(trigger_participation_pct, 0) >= 0.5
    AND NOT (
        LOWER(COALESCE(trigger_description, '')) LIKE '%out for season%'
        OR LOWER(COALESCE(trigger_description, '')) LIKE '%out for the season%'
    )
