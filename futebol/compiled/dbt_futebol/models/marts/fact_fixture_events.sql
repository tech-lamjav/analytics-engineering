

WITH events AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixture_events`
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
    e.fixture_id,
    f.competition,
    f.competition_id,
    f.season,
    f.date_utc,

    e.event_order,
    e.minute,
    e.minute_extra,

    e.team_id,
    e.team_name,
    CASE
        WHEN e.team_id = f.home_team_id THEN 'home'
        WHEN e.team_id = f.away_team_id THEN 'away'
    END                                          AS team_side,

    e.player_id,
    e.player_name,
    e.assist_player_id,
    e.assist_player_name,

    e.event_type,
    e.event_detail,
    e.event_comments,

    e.loaded_at         AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM events e
INNER JOIN fixtures f ON e.fixture_id = f.fixture_id
-- Defensivo: 1 arquivo por fixture já garante event_order único por jogo.
-- Mantém o idioma de dedup de fact_fixtures/fact_fixture_stats.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY e.fixture_id, e.event_order
    ORDER BY e.loaded_at DESC
) = 1