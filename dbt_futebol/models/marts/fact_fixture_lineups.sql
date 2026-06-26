{{ config(
    materialized='table',
    partition_by={'field': 'date_utc', 'data_type': 'date'},
    cluster_by=['fixture_id', 'team_id'],
    description='Formação e técnico por time por jogo (/fixtures/lineups). 2 linhas por fixture_id (mandante e visitante) — insumo de desfalques p/ o modelo. Particionada por DATE(date_utc) e clusterizada por (fixture_id, team_id). Latest-wins: dedup por (fixture_id, team_id) mantendo o loaded_at mais recente — "real" (pós-jogo) vence "confirmed" (~T-30min); lineup_phase mostra qual snapshot venceu. Cobre Brasileirão (71) 2024/25/26 e Copa do Mundo (1) 2026.'
) }}

WITH lineups AS (
    SELECT * FROM {{ ref('stg_futebol_fixture_lineups') }}
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
    l.fixture_id,
    f.competition,
    f.competition_id,
    f.season,
    f.date_utc,

    l.team_id,
    l.team_name,
    CASE
        WHEN l.team_id = f.home_team_id THEN 'home'
        WHEN l.team_id = f.away_team_id THEN 'away'
    END                                          AS team_side,

    l.formation,
    l.coach_id,
    l.coach_name,
    l.lineup_phase,

    l.loaded_at         AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM lineups l
INNER JOIN fixtures f ON l.fixture_id = f.fixture_id
-- Latest-wins: "real" (pós-jogo, loaded_at maior) vence "confirmed" (~T-30min).
-- Mantém o idioma de dedup de fact_fixture_stats/events. Desempate determinístico por
-- lineup_phase='real' (em loaded_at empatado, "real" vence — regra explícita, tie-stable).
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.fixture_id, l.team_id
    ORDER BY l.loaded_at DESC, (l.lineup_phase = 'real') DESC
) = 1
