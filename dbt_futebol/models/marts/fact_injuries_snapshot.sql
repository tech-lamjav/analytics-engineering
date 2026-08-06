{{ config(
    materialized='table',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['team_id', 'fixture_id'],
    description='Snapshot diário de lesionados/suspensos (/injuries). N linhas por (liga, season, snapshot_date) — 1 por (player, fixture, injury_type, injury_reason). Input de modelagem que a maioria dos modelos públicos ignora: desfalque de peça muda materialmente a previsão. O raw é date-stampado no GCS (1 arquivo/dia, acumula histórico) e o rebuild full lê todos os dias. Self-contained: competition vem de requested_league_id, sem joins. Particionada por snapshot_date, clusterizada por (team_id, fixture_id). Dedup por (league_id, season, snapshot_date, fixture_id, player_id, injury_type, injury_reason) mantendo o loaded_at mais recente — a API repete linhas exatas; re-run no mesmo dia não duplica (idempotente). ⚠️ Coverage: Brasileirão (71) 2024/25/26, La Liga (140) 2024/2025/2026 (1ª europeia da expansão com injuries=TRUE — probe 2026-07-15) E Premier League (39) 2024/2025/2026 (probe 2026-07-17; season-log 2026/27 de ambas flipa ao iniciar a temporada) — Copa do Mundo (1), Série B (72), Copa do Brasil (73), Libertadores (13) e Sudamericana (11) têm coverage.injuries=FALSE e ficam fora (os WHEN 72/73/13/11 do CASE existem só por uniformidade e nunca terão linhas; os WHEN 140 e 39 SIM terão linhas reais). Nota: Libertadores 2025 TEVE coverage.injuries=TRUE — rechecar 2026 em agosto via dim_leagues antes de decidir ligar; Sudamericana FALSE em 2024/25/26 (validado 2026-07-14), exclusão simples sem recheck.'
) }}

WITH injuries AS (
    SELECT * FROM {{ ref('stg_futebol_injuries') }}
)

SELECT
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        WHEN 72 THEN 'serie_b'
        WHEN 73 THEN 'copa_do_brasil'
        WHEN 13 THEN 'libertadores'
        WHEN 11 THEN 'sudamericana'
        WHEN 140 THEN 'la_liga'
        WHEN 39 THEN 'premier_league'
        WHEN 2  THEN 'champions_league'
        WHEN 135 THEN 'serie_a_ita'
        WHEN 78  THEN 'bundesliga'
        WHEN 61  THEN 'ligue_1'
        ELSE 'unknown'
    END                                          AS competition,
    requested_league_id                          AS league_id,
    requested_season                             AS season,
    snapshot_date,

    team_id,
    team_name,
    team_logo,

    player_id,
    player_name,
    player_photo,

    fixture_id,
    fixture_date,

    injury_type,
    injury_reason,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM injuries
-- Idempotência + dedup das linhas EXATAS que a API repete: granularidade = 1 linha por
-- (player, fixture, type, reason) por snapshot. Re-run no mesmo dia sobrescreve o arquivo
-- no GCS e o QUALIFY segura qualquer resíduo.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY requested_league_id, requested_season, snapshot_date,
                 fixture_id, player_id, injury_type, injury_reason
    ORDER BY loaded_at DESC
) = 1
