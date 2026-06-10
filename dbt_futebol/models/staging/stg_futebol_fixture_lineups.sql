{{ config(
    description='Flatten do raw_futebol_fixture_lineups (nível time). 2 linhas por (fixture, fase) — formation e coach de cada time. lineup_phase distingue confirmed (escalação ~T-30min) de real (pós-jogo); fact_fixture_lineups faz dedup latest-wins por loaded_at e junta fact_fixtures p/ competition/season/date_utc e rótulo home/away.'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_fixture_lineups') }}
)

SELECT
    src.fixture_id,
    src.loaded_at,
    src.lineup_phase,

    src.team.id         AS team_id,
    src.team.name       AS team_name,

    src.formation,

    src.coach.id        AS coach_id,
    src.coach.name      AS coach_name
FROM src
