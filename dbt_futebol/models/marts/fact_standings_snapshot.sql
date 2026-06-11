{{ config(
    materialized='table',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['league_id', 'team_id'],
    description='Snapshot diário da tabela do campeonato (/standings). N linhas por (liga, season, snapshot_date) — 1 por time×grupo (na Copa o time aparece no grupo e no "Ranking of third-placed teams"). Contexto de modelagem (briga pelo G4, rebaixamento, jogo já decidido) e histórico de evolução: o raw é date-stampado no GCS (1 arquivo/dia, acumula), e o rebuild full lê todos os dias. Self-contained: competition vem de requested_league_id, sem joins. Dedup por (league_id, season, snapshot_date, group_name, team_id) mantendo o loaded_at mais recente — re-run no mesmo dia não duplica (idempotente). Backfill 2024/2025 = tabela FINAL com snapshot_date do dia da coleta (standings_updated_at marca a última atualização real na API). Cobre Brasileirão (71) 2024/25/26 e Copa do Mundo (1) 2026.'
) }}

WITH standings AS (
    SELECT * FROM {{ ref('stg_futebol_standings') }}
)

SELECT
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        ELSE 'unknown'
    END                                          AS competition,
    requested_league_id                          AS league_id,
    requested_season                             AS season,
    snapshot_date,

    team_id,
    team_name,
    team_logo,
    rank,
    points,
    goals_diff,
    group_name,
    form,
    rank_status,
    rank_description,
    standings_updated_at,

    -- campanha geral
    played_total,
    wins_total,
    draws_total,
    loses_total,
    goals_for_total,
    goals_against_total,

    -- campanha como mandante
    played_home,
    wins_home,
    draws_home,
    loses_home,
    goals_for_home,
    goals_against_home,

    -- campanha como visitante
    played_away,
    wins_away,
    draws_away,
    loses_away,
    goals_for_away,
    goals_against_away,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM standings
-- Idempotência: re-run no mesmo dia sobrescreve o arquivo no GCS e o dedup
-- segura qualquer resíduo. group_name na chave: na Copa o mesmo time aparece
-- no grupo E no "Ranking of third-placed teams" — são duas linhas legítimas.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY requested_league_id, requested_season, snapshot_date, group_name, team_id
    ORDER BY loaded_at DESC
) = 1
