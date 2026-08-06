{{ config(
    materialized='table',
    partition_by={'field': 'snapshot_date', 'data_type': 'date'},
    cluster_by=['team_id', 'fixture_id'],
    description='Snapshot diário de lesionados/suspensos (/injuries). N linhas por (liga, season, snapshot_date) — 1 por (player, fixture, injury_type, injury_reason). Input de modelagem que a maioria dos modelos públicos ignora: desfalque de peça muda materialmente a previsão. O raw é date-stampado no GCS (1 arquivo/dia, acumula histórico) e o rebuild full lê todos os dias. Self-contained: competition vem de requested_league_id, sem joins. Particionada por snapshot_date, clusterizada por (team_id, fixture_id). Dedup por (league_id, season, snapshot_date, fixture_id, player_id, injury_type, injury_reason) mantendo o loaded_at mais recente — a API repete linhas exatas; re-run no mesmo dia não duplica (idempotente). ⚠️ Coverage: este CASE tem um WHEN por liga coletada, mas só as ligas com coverage.injuries=TRUE produzem linhas — os demais WHEN existem por uniformidade e ficam sempre vazios. A lista de quem está ligado é INJURIES_CURRENT / INJURIES_BACKFILL / FUTEBOL_INJURIES_LEAGUE_IDS na configuração da ingestão, que é a fonte única; não é enumerada aqui porque enumerar já deixou esta nota errada 3 vezes. Em geral: 1ª divisão europeia e Brasileirão = TRUE; mata-mata e Copa do Mundo = FALSE. Caveats que NÃO se derivam da regra: Libertadores (13) foi FALSE em 2024/2026 mas TRUE em 2025 — rechecar via dim_leagues antes de ligar; Sudamericana (11) FALSE em 2024/25/26 (validado 2026-07-14), exclusão simples sem recheck; season-log de temporada nova aparece FALSE por pré-temporada e flipa na abertura, o que NÃO é motivo p/ deixar a liga fora.'
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
