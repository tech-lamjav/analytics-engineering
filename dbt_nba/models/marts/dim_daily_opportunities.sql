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
        dsp.rating_stars,
        -- Stat-specific opponent rankings (rank 30 = most conceded = weakest defense)
        tos.opp_pts_rank AS opponent_opp_pts_rank,
        tos.opp_reb_rank AS opponent_opp_reb_rank,
        tos.opp_ast_rank AS opponent_opp_ast_rank,
        tos.opp_fg3_pct_rank AS opponent_opp_fg3_pct_rank
    FROM with_opponent wo
    LEFT JOIN {{ ref('dim_teams') }} opp ON wo.opponent_team_id = opp.team_id
    LEFT JOIN {{ ref('dim_team_opponent_stats') }} tos ON wo.opponent_team_id = tos.team_id
    LEFT JOIN {{ ref('dim_stat_player') }} dsp
        ON wo.backup_player_id = dsp.player_id
        AND wo.stat_type = dsp.stat_type
),

with_spreads AS (
    SELECT
        wc.*,
        sbo.spread,
        sbo.total AS game_total
    FROM with_context wc
    LEFT JOIN {{ ref('stg_betting_odds') }} sbo ON wc.game_id = sbo.game_id
),

with_scores AS (
    SELECT
        c.*,
        CASE
            WHEN c.spread IS NULL       THEN 1.0
            WHEN ABS(c.spread) <= 7     THEN 1.0
            WHEN ABS(c.spread) <= 12    THEN 0.85
            WHEN ABS(c.spread) <= 17    THEN 0.70
            ELSE                             0.70  -- 18+ usa 0.70 + cap 50 aplicado no scored
        END AS blowout_deflator,
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
        -- Stat-specific matchup score: rank 30 = most conceded = weakest defense = best matchup (score 90)
        CASE
            WHEN c.stat_type = 'player_rebounds' THEN
                CASE WHEN c.opponent_opp_reb_rank >= 21 THEN 90 WHEN c.opponent_opp_reb_rank >= 11 THEN 60 WHEN c.opponent_opp_reb_rank IS NOT NULL THEN 30 ELSE 60 END
            WHEN c.stat_type = 'player_assists' THEN
                CASE WHEN c.opponent_opp_ast_rank >= 21 THEN 90 WHEN c.opponent_opp_ast_rank >= 11 THEN 60 WHEN c.opponent_opp_ast_rank IS NOT NULL THEN 30 ELSE 60 END
            WHEN c.stat_type = 'player_points' THEN
                CASE WHEN c.opponent_opp_pts_rank >= 21 THEN 90 WHEN c.opponent_opp_pts_rank >= 11 THEN 60 WHEN c.opponent_opp_pts_rank IS NOT NULL THEN 30 ELSE 60 END
            WHEN c.stat_type = 'player_threes' THEN
                CASE WHEN c.opponent_opp_fg3_pct_rank >= 21 THEN 90 WHEN c.opponent_opp_fg3_pct_rank >= 11 THEN 60 WHEN c.opponent_opp_fg3_pct_rank IS NOT NULL THEN 30 ELSE 60 END
            ELSE
                CASE WHEN c.opponent_def_rank IS NOT NULL AND c.opponent_def_rank >= 21 THEN 90
                     WHEN c.opponent_def_rank IS NOT NULL AND c.opponent_def_rank >= 11 THEN 60
                     WHEN c.opponent_def_rank IS NOT NULL THEN 30
                     ELSE 60 END
        END AS matchup_score,
        CASE
            WHEN c.game_total IS NULL  THEN 60
            WHEN c.game_total >= 228   THEN 80
            WHEN c.game_total >= 218   THEN 60
            ELSE                            30
        END AS ambient_score,
        CASE
            WHEN c.cv_sem IS NULL THEN 60
            WHEN c.cv_sem < 20 THEN 90
            WHEN c.cv_sem <= 35 THEN 60
            ELSE 20
        END AS cv_score
    FROM with_spreads c
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

with_final_score AS (
    SELECT
        sc.*,
        CAST(ROUND(sc.score_base_raw) AS INT64) AS score_base,
        -- cap em 50 quando spread >= 18 pts (blowout critico)
        CASE
            WHEN sc.spread IS NOT NULL AND ABS(sc.spread) >= 18
                THEN LEAST(CAST(ROUND(sc.score_base_raw * sc.blowout_deflator) AS INT64), 50)
            ELSE CAST(ROUND(sc.score_base_raw * sc.blowout_deflator) AS INT64)
        END AS score
    FROM scored sc
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
        score_base,
        score,
        CASE
            WHEN score >= 80 THEN 'ALTA CONFIANCA'
            WHEN score >= 60 THEN 'MEDIA CONFIANCA'
            WHEN score >= 40 THEN 'BAIXA CONFIANCA'
            ELSE 'SEM OPORTUNIDADE'
        END AS score_label,
        opponent_abbr,
        opponent_def_rank,
        opponent_off_rank,
        opponent_opp_pts_rank,
        opponent_opp_reb_rank,
        opponent_opp_ast_rank,
        opponent_opp_fg3_pct_rank,
        is_home,
        rating_stars,
        spread,
        blowout_deflator,
        game_total,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM with_final_score
    WHERE score >= 40
      AND line_value IS NOT NULL                              -- Stage 3C: sem line publicada nao e oportunidade apostavel
      AND trigger_freshness IN ('NOVA', 'RECENTE')           -- Stage 2.5: EXTENDIDA (8-14d) vai para dim_teammate_impact_360 mas nao para oportunidades
)

SELECT * FROM final
