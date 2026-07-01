

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_fixtures`
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.loaded_at,

    -- fixture
    src.fixture.id              AS fixture_id,
    src.fixture.referee         AS referee,
    src.fixture.timezone        AS timezone,
    src.fixture.timestamp       AS timestamp_unix,  -- epoch UTC (base do date_utc)
    src.fixture.venue.id        AS venue_id,
    src.fixture.venue.name      AS venue_name,
    src.fixture.venue.city      AS venue_city,
    src.fixture.status.long     AS status_long,
    src.fixture.status.short    AS status_short,
    src.fixture.status.elapsed  AS status_elapsed,

    -- league
    src.league.round            AS round,

    -- teams
    src.teams.home.id           AS home_team_id,
    src.teams.home.name         AS home_team_name,
    src.teams.home.winner       AS home_team_winner,
    src.teams.away.id           AS away_team_id,
    src.teams.away.name         AS away_team_name,
    src.teams.away.winner       AS away_team_winner,

    -- goals (tempo normal)
    src.goals.home              AS goals_home,
    src.goals.away              AS goals_away,

    -- score (por etapa)
    src.score.halftime.home     AS score_halftime_home,
    src.score.halftime.away     AS score_halftime_away,
    src.score.fulltime.home     AS score_fulltime_home,
    src.score.fulltime.away     AS score_fulltime_away,
    src.score.extratime.home    AS score_extratime_home,
    src.score.extratime.away    AS score_extratime_away,
    src.score.penalty.home      AS score_penalty_home,
    src.score.penalty.away      AS score_penalty_away
FROM src