

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_fixture_events`
)

SELECT
    src.fixture_id,
    src.event_order,
    src.loaded_at,

    src.elapsed         AS minute,
    src.extra           AS minute_extra,

    src.team.id         AS team_id,
    src.team.name       AS team_name,

    src.player.id       AS player_id,
    src.player.name     AS player_name,

    src.assist.id       AS assist_player_id,
    src.assist.name     AS assist_player_name,

    src.type            AS event_type,
    src.detail          AS event_detail,
    src.comments        AS event_comments
FROM src