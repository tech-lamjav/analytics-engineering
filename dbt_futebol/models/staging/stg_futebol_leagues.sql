{{ config(
    description='Flatten do raw_futebol_leagues. 1 linha por (league_id, season_year). UNNEST do array seasons + filtro defensivo pela season requisitada (a API hoje respeita o filtro, mas se mudar o staging ainda fica correto).'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_leagues') }}
),

unnested AS (
    SELECT
        src.requested_league_id,
        src.requested_season,
        src.loaded_at,
        src.league.id        AS league_id,
        src.league.name      AS league_name,
        src.league.type      AS league_type,
        src.league.logo      AS league_logo_url,
        src.country.name     AS country_name,
        src.country.code     AS country_code,
        src.country.flag     AS country_flag_url,
        s.year               AS season_year,
        s.start              AS season_start,
        s.`end`              AS season_end,
        s.current            AS season_current,
        s.coverage           AS coverage
    FROM src, UNNEST(src.seasons) AS s
)

SELECT *
FROM unnested
-- Defensivo: hoje a API filtra corretamente por &season=, mas se voltar a ecoar
-- todas as seasons o staging continua produzindo só a linha que pedimos.
WHERE season_year = requested_season
