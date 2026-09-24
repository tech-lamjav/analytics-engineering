
-- GUARDA DE RECONSTRUÇÃO do fact_insumos_medidos (AE#175, ADR 0016) — mesmo idioma de
-- assert_funil_insumos_medidos_reconstroi.sql (AE#153): serializa os dois lados via
-- TO_JSON_STRING, ordenados por (premissa, insumo) pra serialização determinística, e
-- compara CONTEÚDO, não só contagem. Uma comparação só de COUNT(*)/ARRAY_LENGTH não pegaria
-- um UNNEST que trocasse `valor` por engano (mesma quantidade de linhas, dado errado) — só
-- pegaria perda/duplicação de linha, e mesmo isso é estruturalmente impossível hoje com o
-- SELECT correlacionado do model.sql (COUNT(*) por linha é, por construção, sempre igual a
-- ARRAY_LENGTH). A comparação de conteúdo é o que realmente sobrevive a uma mudança futura
-- no SQL do modelo.
--
-- tag:guarda desde a AE#202 — a tabela entrou no --select dos dois workflows que reconstroem
-- os pais (DE#85, 16/09), a condição que a AE#175 deixou escrita para ligar a tag.
--
-- AE#202: cobre os dois mercados publicados (1X2 e Handicap). A chave de comparação inclui
-- market e LINHA — no Handicap o mesmo (fixture, outcome) tem várias linhas, cada uma com o
-- seu conjunto de premissas. A linha entra como texto (line_key, 'NONE' quando NULL) porque o
-- 1X2 não tem linha e NULL = NULL não casaria no FULL OUTER JOIN.

WITH origem AS (
    SELECT
        fixture_id,
        outcome,
        'match_winner' AS market,
        'NONE' AS line_key,
        TO_JSON_STRING(
            ARRAY(
                SELECT AS STRUCT premissa, insumo, valor
                FROM UNNEST(insumos_medidos)
                ORDER BY premissa, insumo
            )
        ) AS insumos_serializados
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`

    UNION ALL

    SELECT
        fixture_id,
        outcome,
        'asian_handicap' AS market,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key,
        TO_JSON_STRING(
            ARRAY(
                SELECT AS STRUCT premissa, insumo, valor
                FROM UNNEST(insumos_medidos)
                ORDER BY premissa, insumo
            )
        ) AS insumos_serializados
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
),

achatado AS (
    SELECT
        fixture_id,
        outcome,
        market,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key,
        TO_JSON_STRING(
            ARRAY_AGG(STRUCT(premissa, insumo, valor) ORDER BY premissa, insumo)
        ) AS insumos_serializados
    FROM `smartbetting-dados`.`futebol`.`fact_insumos_medidos`
    GROUP BY fixture_id, outcome, market, line_key
)

SELECT
    COALESCE(o.fixture_id, a.fixture_id) AS fixture_id,
    COALESCE(o.outcome, a.outcome) AS outcome,
    COALESCE(o.market, a.market) AS market,
    COALESCE(o.line_key, a.line_key) AS line_key,
    COALESCE(o.insumos_serializados, '[]') AS insumos_medidos_origem,
    COALESCE(a.insumos_serializados, '[]') AS insumos_medidos_achatado
FROM origem AS o
FULL OUTER JOIN achatado AS a
    ON o.fixture_id = a.fixture_id
   AND o.outcome = a.outcome
   AND o.market = a.market
   AND o.line_key = a.line_key
WHERE COALESCE(o.insumos_serializados, '[]') != COALESCE(a.insumos_serializados, '[]')