{{ config(
    materialized='table',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['team_id', 'season'],
    description='Agregados de temporada por time (/teams/statistics). 1 linha por (team_id, liga, season) — input direto pro modelo Poisson (força ataque/defesa, médias casa/fora). Self-contained: competition/season vêm da própria resposta (sem join em fact_fixtures). Latest-only: particionada por snapshot_date (data da coleta) e clusterizada por (team_id, season); reconstruída full a cada run (o GCS guarda só o snapshot mais recente por mode). Dedup por (team_id, liga, season) mantendo o loaded_at mais recente. Cobre Brasileirão (71) 2024/25/26 e Copa do Mundo (1) 2026.'
) }}

WITH stats AS (
    SELECT * FROM {{ ref('stg_futebol_team_season_stats') }}
)

SELECT
    team_id,
    team_name,
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        ELSE 'unknown'
    END                                          AS competition,
    requested_league_id                          AS competition_id,
    requested_season                             AS season,
    snapshot_date,
    form,

    -- jogos / resultados (casa/fora/total)
    played_home,
    played_away,
    played_total,
    wins_home,
    wins_away,
    wins_total,
    draws_home,
    draws_away,
    draws_total,
    loses_home,
    loses_away,
    loses_total,

    -- gols marcados (insumo de força de ataque)
    goals_for_home,
    goals_for_away,
    goals_for_total,
    goals_for_avg_home,
    goals_for_avg_away,
    goals_for_avg_total,

    -- gols sofridos (insumo de força de defesa)
    goals_against_home,
    goals_against_away,
    goals_against_total,
    goals_against_avg_home,
    goals_against_avg_away,
    goals_against_avg_total,

    -- defesa / ataque agregados
    clean_sheet_home,
    clean_sheet_away,
    clean_sheet_total,
    failed_to_score_home,
    failed_to_score_away,
    failed_to_score_total,

    -- maiores marcas
    biggest_streak_wins,
    biggest_streak_draws,
    biggest_streak_loses,
    biggest_win_home,
    biggest_win_away,
    biggest_lose_home,
    biggest_lose_away,
    biggest_goals_for_home,
    biggest_goals_for_away,
    biggest_goals_against_home,
    biggest_goals_against_away,

    -- pênaltis
    penalty_scored_total,
    penalty_scored_pct,
    penalty_missed_total,
    penalty_missed_pct,
    penalty_total,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM stats
-- Latest-only: 1 arquivo por mode já garante 1 linha por (time, liga, season).
-- Mantém o idioma de dedup de fact_fixtures/dim_teams.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY team_id, requested_league_id, requested_season
    ORDER BY loaded_at DESC
) = 1
