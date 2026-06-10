{{ config(
    description='Flatten do raw_futebol_fixture_lineups (nível jogador). ~22-30 linhas por (fixture, fase): startXI (is_starter=TRUE) + substitutes (is_starter=FALSE), dos dois times. player_slot = índice no array (WITH OFFSET; preserva a ordem). lineup_phase distingue confirmed/real; fact_fixture_lineups_players faz dedup latest-wins por loaded_at.'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_fixture_lineups') }}
),

starters AS (
    SELECT
        src.fixture_id,
        src.loaded_at,
        src.lineup_phase,
        src.team.id     AS team_id,
        src.team.name   AS team_name,
        TRUE            AS is_starter,
        p_offset        AS player_slot,
        p.player.id     AS player_id,
        p.player.name   AS player_name,
        p.player.number AS shirt_number,
        p.player.pos    AS position,
        p.player.grid   AS grid
    FROM src, UNNEST(src.startXI) AS p WITH OFFSET AS p_offset
),

bench AS (
    SELECT
        src.fixture_id,
        src.loaded_at,
        src.lineup_phase,
        src.team.id     AS team_id,
        src.team.name   AS team_name,
        FALSE           AS is_starter,
        p_offset        AS player_slot,
        p.player.id     AS player_id,
        p.player.name   AS player_name,
        p.player.number AS shirt_number,
        p.player.pos    AS position,
        p.player.grid   AS grid
    FROM src, UNNEST(src.substitutes) AS p WITH OFFSET AS p_offset
)

SELECT * FROM starters
UNION ALL
SELECT * FROM bench
