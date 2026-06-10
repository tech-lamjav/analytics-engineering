{{ config(
    materialized='table',
    partition_by={'field': 'date_utc', 'data_type': 'date'},
    cluster_by=['fixture_id', 'team_id'],
    description='Escalação de jogadores por jogo (/fixtures/lineups). ~22-30 linhas por fixture_id (titulares + reservas dos dois times) — base p/ ajustar o modelo por desfalques. is_starter separa startXI de substitutes; position/grid/shirt_number do jogador. Particionada por DATE(date_utc) e clusterizada por (fixture_id, team_id). Latest-wins: dedup por (fixture_id, player_id) mantendo o loaded_at mais recente — "real" vence "confirmed". Cobre Brasileirão (71) 2024/25/26 e Copa do Mundo (1) 2026.'
) }}

WITH players AS (
    SELECT * FROM {{ ref('stg_futebol_fixture_lineups_players') }}
),

fixtures AS (
    SELECT
        fixture_id,
        competition,
        competition_id,
        season,
        date_utc,
        home_team_id,
        away_team_id
    FROM {{ ref('fact_fixtures') }}
)

SELECT
    p.fixture_id,
    f.competition,
    f.competition_id,
    f.season,
    f.date_utc,

    p.team_id,
    p.team_name,
    CASE
        WHEN p.team_id = f.home_team_id THEN 'home'
        WHEN p.team_id = f.away_team_id THEN 'away'
    END                                          AS team_side,

    p.is_starter,
    p.player_slot,
    p.player_id,
    p.player_name,
    p.shirt_number,
    p.position,
    p.grid,
    p.lineup_phase,

    p.loaded_at         AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM players p
INNER JOIN fixtures f ON p.fixture_id = f.fixture_id
-- Latest-wins: "real" (pós-jogo) vence "confirmed" (~T-30min). Um jogador aparece 1x por
-- fase; dedup por (fixture_id, player_id) mantém a fase mais recente.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.fixture_id, p.player_id
    ORDER BY p.loaded_at DESC
) = 1
