

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_teams`
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.loaded_at,
    src.team.id         AS team_id,
    src.team.name       AS team_name,
    src.team.code       AS team_code,
    src.team.country    AS team_country,
    src.team.founded    AS team_founded_year,
    src.team.national   AS national,
    src.team.logo       AS team_logo_url,
    src.venue.id        AS venue_id,
    src.venue.name      AS venue_name,
    src.venue.address   AS venue_address,
    src.venue.city      AS venue_city,
    src.venue.capacity  AS venue_capacity,
    src.venue.surface   AS venue_surface,
    src.venue.image     AS venue_image_url
FROM src