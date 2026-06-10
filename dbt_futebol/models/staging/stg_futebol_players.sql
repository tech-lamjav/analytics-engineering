{{ config(
    description='Flatten do raw_futebol_players. 1 linha por (player_id, requested_league_id, requested_season). position vem de statistics[0].games.position (não existe no objeto player). dim_players faz o dedup por player_id.'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_players') }}
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.loaded_at,
    src.player.id          AS player_id,
    src.player.name        AS player_name,
    src.player.firstname   AS first_name,
    src.player.lastname    AS last_name,
    src.player.age         AS age,
    src.player.birth.date  AS birth_date,
    src.player.nationality AS nationality,
    src.player.height      AS height,
    src.player.weight      AS weight,
    src.player.injured     AS injured,
    src.player.photo       AS photo_url,
    src.statistics[SAFE_OFFSET(0)].games.position AS position
FROM src
