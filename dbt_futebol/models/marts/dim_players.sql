{{ config(
    materialized='table',
    description='Dimensão de jogadores. 1 linha por player_id. Fonte primária: catálogo /players (metadados ricos — age/nacionalidade/altura/..., dedup pela season mais recente). Fallback: jogadores que entraram em campo (via stg_futebol_fixture_player_stats) mas faltam no catálogo entram só com id/nome/foto/posição (demais NULL). source distingue a origem (catalog|fixture_only) e garante que todo player_id de fact_fixture_player_stats tenha entrada aqui. Inclui Brasileirão e Copa do Mundo.'
) }}

WITH catalog AS (
    -- Catálogo /players: fonte da verdade dos metadados. Ordenar por season DESC
    -- mantém age/posição atuais.
    SELECT
        player_id,
        player_name,
        first_name,
        last_name,
        age,
        birth_date,
        nationality,
        height,
        weight,
        position,
        photo_url,
        loaded_at AS extracted_at,
        'catalog' AS source
    FROM {{ ref('stg_futebol_players') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY player_id
        ORDER BY requested_season DESC, loaded_at DESC
    ) = 1
),

fixture_only AS (
    -- Jogadores que apareceram em /fixtures/players mas NÃO estão no catálogo
    -- (ex.: transferências no meio da temporada, lacunas de paginação do catálogo).
    -- Entram só com id/nome/foto/posição (do próprio jogo); demais metadados NULL.
    -- Tipos alinhados ao bloco catalog p/ o UNION ALL (birth_date é DATE, age INT64).
    SELECT
        f.player_id,
        f.player_name,
        CAST(NULL AS STRING) AS first_name,
        CAST(NULL AS STRING) AS last_name,
        CAST(NULL AS INT64)  AS age,
        CAST(NULL AS DATE)   AS birth_date,
        CAST(NULL AS STRING) AS nationality,
        CAST(NULL AS STRING) AS height,
        CAST(NULL AS STRING) AS weight,
        f.position,
        f.player_photo AS photo_url,
        f.loaded_at AS extracted_at,
        'fixture_only' AS source
    FROM {{ ref('stg_futebol_fixture_player_stats') }} f
    WHERE NOT EXISTS (
        SELECT 1 FROM catalog c WHERE c.player_id = f.player_id
    )
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY f.player_id
        ORDER BY f.loaded_at DESC
    ) = 1
),

unioned AS (
    SELECT * FROM catalog
    UNION ALL
    SELECT * FROM fixture_only
)

SELECT
    player_id,
    player_name,
    first_name,
    last_name,
    age,
    birth_date,
    nationality,
    height,
    weight,
    position,
    photo_url,
    extracted_at,
    source,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM unioned
