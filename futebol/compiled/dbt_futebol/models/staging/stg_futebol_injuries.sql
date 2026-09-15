

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_injuries`
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.snapshot_date,
    src.loaded_at,

    src.player.id     AS player_id,
    src.player.name   AS player_name,
    src.player.photo  AS player_photo,
    src.player.type   AS injury_type,    -- ⚠️ type/reason vêm ANINHADOS em player (não no topo)
    src.player.reason AS injury_reason,

    src.team.id   AS team_id,
    src.team.name AS team_name,
    src.team.logo AS team_logo,

    src.fixture.id        AS fixture_id,
    src.fixture.date      AS fixture_date,
    src.fixture.timestamp AS fixture_timestamp,

    src.league.name AS league_name
FROM src
-- Defensivo: ignora eventual linha metadata-only (arquivo subido sem injuries)
WHERE src.player.id IS NOT NULL