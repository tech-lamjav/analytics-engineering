

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_fixture_lineups`
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