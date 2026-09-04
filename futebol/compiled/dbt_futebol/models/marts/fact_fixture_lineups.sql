

WITH lineups AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixture_lineups`
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
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
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