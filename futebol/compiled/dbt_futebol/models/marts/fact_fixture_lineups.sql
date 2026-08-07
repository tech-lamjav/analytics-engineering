

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
-- Latest-wins: "real" (pós-jogo, loaded_at maior) vence "confirmed" (~T-30min).
-- Mantém o idioma de dedup de fact_fixture_stats/events. Desempate determinístico por
-- lineup_phase='real' (em loaded_at empatado, "real" vence — regra explícita, tie-stable).
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.fixture_id, l.team_id
    ORDER BY l.loaded_at DESC, (l.lineup_phase = 'real') DESC
) = 1