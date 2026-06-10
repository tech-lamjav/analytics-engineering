{{ config(
    description='Flatten + pivot do raw_futebol_fixture_statistics. 1 linha por (fixture_id, team_id) — 2 por jogo. Pivota o array statistics[{type,value}] em colunas tipadas (SAFE_CAST; Ball Possession e Passes % têm o "%" removido). value vem stringificado do extractor. fact_fixture_stats junta fact_fixtures p/ competition/season/date_utc e rótulo home/away.'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_fixture_statistics') }}
)

SELECT
    src.fixture_id,
    src.team.id    AS team_id,
    src.team.name  AS team_name,
    src.loaded_at,

    -- pivot: 1 subquery correlacionada por tipo (strings exatas da API-Football v3)
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Shots on Goal')    AS INT64) AS shots_on_goal,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Shots off Goal')   AS INT64) AS shots_off_goal,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Total Shots')      AS INT64) AS total_shots,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Blocked Shots')    AS INT64) AS blocked_shots,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Shots insidebox')  AS INT64) AS shots_insidebox,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Shots outsidebox') AS INT64) AS shots_outsidebox,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Fouls')            AS INT64) AS fouls,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Corner Kicks')     AS INT64) AS corner_kicks,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Offsides')         AS INT64) AS offsides,
    SAFE_CAST(REPLACE((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Ball Possession'), '%', '') AS INT64) AS ball_possession,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Yellow Cards')     AS INT64) AS yellow_cards,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Red Cards')        AS INT64) AS red_cards,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Goalkeeper Saves') AS INT64) AS goalkeeper_saves,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Total passes')     AS INT64) AS total_passes,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Passes accurate')  AS INT64) AS passes_accurate,
    SAFE_CAST(REPLACE((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'Passes %'), '%', '') AS INT64) AS passes_pct,

    -- stats avançados que a própria API-Football v3 já fornece (valores decimais)
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'expected_goals')  AS FLOAT64) AS expected_goals,
    SAFE_CAST((SELECT s.value FROM UNNEST(src.statistics) AS s WHERE s.type = 'goals_prevented') AS FLOAT64) AS goals_prevented
FROM src
