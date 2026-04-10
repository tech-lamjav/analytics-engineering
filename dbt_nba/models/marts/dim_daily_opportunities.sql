{{
  config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'game_date', 'data_type': 'date'},
    on_schema_change='append_new_columns',
    post_hook=[
      "DELETE FROM {{ this }} WHERE game_date < DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 DAY)"
    ],
    description='Daily betting opportunities: COM vs SEM 360 analysis, lines, contextual validation, and 0-100 score',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH base AS (
    SELECT * FROM {{ ref('int_daily_360_analysis') }}
),

with_opponent AS (
    SELECT
        b.*,
        fg.home_team_id,
        fg.visitor_team_id,
        CASE
            WHEN b.trigger_team_id = fg.home_team_id THEN fg.visitor_team_id
            ELSE fg.home_team_id
        END AS opponent_team_id,
        CASE
            WHEN b.trigger_team_id = fg.home_team_id THEN fg.visitor_team_abbreviation
            ELSE fg.home_team_abbreviation
        END AS opponent_abbr
    FROM base b
    INNER JOIN {{ ref('ft_games') }} fg ON b.game_id = fg.game_id
),

with_context AS (
    SELECT
        wo.*,
        opp.team_defensive_rating_rank AS opponent_def_rank,
        opp.team_offensive_rating_rank AS opponent_off_rank,
        dsp.rating_stars
    FROM with_opponent wo
    LEFT JOIN {{ ref('dim_teams') }} opp ON wo.opponent_team_id = opp.team_id
    LEFT JOIN {{ ref('dim_stat_player') }} dsp
        ON wo.backup_player_id = dsp.player_id
        AND wo.stat_type = dsp.stat_type
),

with_scores AS (
    SELECT
        c.*,
        CAST(NULL AS FLOAT64) AS spread,  -- TODO: plugar spread coletado (task coleta spread/total)
        1.0 AS blowout_deflator,           -- TODO: plugar deflator baseado em spread quando disponivel
        -- gap_score usa apenas gap_vs_line_pct; backups sem line sao filtrados em final
        CASE
            WHEN c.gap_vs_line_pct > 20 THEN 90
            WHEN c.gap_vs_line_pct > 10 THEN 70
            WHEN c.gap_vs_line_pct > 5  THEN 50
            ELSE 20
        END AS gap_score,
        CASE
            WHEN c.jogos_sem >= 10 THEN 90
            WHEN c.jogos_sem >= 5 THEN 70
            ELSE 50
        END AS sample_score,
        CASE
            WHEN c.trigger_days_out <= 2 THEN 90
            WHEN c.trigger_days_out <= 5 THEN 70
            WHEN c.trigger_days_out <= 7 THEN 50
            ELSE 30
        END AS freshness_score,
        CASE
            WHEN c.opponent_def_rank IS NOT NULL AND c.opponent_def_rank <= 10 THEN 90
            WHEN c.opponent_def_rank IS NOT NULL AND c.opponent_def_rank <= 20 THEN 60
            WHEN c.opponent_def_rank IS NOT NULL THEN 30
            ELSE 60
        END AS matchup_score,
        60 AS ambient_score,  -- TODO: substituir por CASE em Total O/U quando coleta de total disponivel
        CASE
            WHEN c.cv_sem IS NULL THEN 60
            WHEN c.cv_sem < 20 THEN 90
            WHEN c.cv_sem <= 35 THEN 60
            ELSE 20
        END AS cv_score
    FROM with_context c
),

scored AS (
    SELECT
        s.*,
        (
            (s.gap_score * 0.30)
            + (s.sample_score * 0.20)
            + (s.freshness_score * 0.20)
            + (s.matchup_score * 0.15)
            + (s.ambient_score * 0.10)
            + (s.cv_score * 0.05)
        ) AS score_base_raw
    FROM with_scores s
),

final AS (
    SELECT
        game_id,
        game_date,
        game_time_brasilia AS game_time,
        home_team_abbr,
        visitor_team_abbr,
        trigger_player_id,
        trigger_name,
        trigger_status,
        trigger_team_abbr,
        trigger_team_id,
        trigger_days_out,
        trigger_freshness,
        trigger_participation_pct,
        is_b2b,
        fatigue_level,
        backup_player_id,
        backup_player_name,
        stat_type,
        avg_com,
        avg_sem,
        stddev_sem,
        cv_sem,
        gap,
        gap_pct,
        jogos_com,
        jogos_sem,
        line_value,
        gap_vs_line,
        gap_vs_line_pct,
        signal,
        CAST(ROUND(score_base_raw) AS INT64) AS score_base,
        CAST(ROUND(score_base_raw * blowout_deflator) AS INT64) AS score,
        CASE
            WHEN ROUND(score_base_raw * blowout_deflator) >= 80 THEN 'ALTA CONFIANCA'
            WHEN ROUND(score_base_raw * blowout_deflator) >= 60 THEN 'MEDIA CONFIANCA'
            WHEN ROUND(score_base_raw * blowout_deflator) >= 40 THEN 'BAIXA CONFIANCA'
            ELSE 'SEM OPORTUNIDADE'
        END AS score_label,
        opponent_abbr,
        opponent_def_rank,
        opponent_off_rank,
        is_home,
        rating_stars,
        spread,
        blowout_deflator,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM scored
    WHERE ROUND(score_base_raw * blowout_deflator) >= 40
      AND line_value IS NOT NULL                              -- Stage 3C: sem line publicada nao e oportunidade apostavel
      AND trigger_freshness IN ('NOVA', 'RECENTE')           -- Stage 2.5: EXTENDIDA (8-14d) vai para dim_teammate_impact_360 mas nao para oportunidades
)

SELECT * FROM final
