{{ config(
    materialized='table',
    partition_by={'field': 'date_utc', 'data_type': 'date'},
    cluster_by=['fixture_id', 'team_id'],
    description='Formação e técnico por time por jogo (/fixtures/lineups). Grão (fixture_id, team_id, lineup_phase): até 4 linhas por fixture_id — os dois times × as duas fases. "confirmed" (~T-30min) e "real" (pós-jogo) COEXISTEM; não são versões melhor e pior uma da outra, são o que se sabia em dois momentos, e a confirmada é a única que existe antes do apito. Particionada por DATE(date_utc) e clusterizada por (fixture_id, team_id). Latest-wins DENTRO de cada fase (dedup por loaded_at), só para absorver re-execução do pipeline. Cobre Brasileirão (71) 2024/25/26 e Copa do Mundo (1) 2026.'
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
-- A fase entra no grão (#38). Antes o dedup era por (fixture_id, team_id) e a "real",
-- que chega depois do jogo, sobrescrevia a "confirmed" — look-ahead entrando pela porta
-- do dedup, e a confirmada é a única evidência pré-apito de quem entra em campo.
-- O latest-wins continua existindo DENTRO de cada fase, com o mesmo idioma de
-- fact_fixture_stats/events, para absorver re-execução do pipeline.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.fixture_id, l.team_id, l.lineup_phase
    ORDER BY l.loaded_at DESC
) = 1
