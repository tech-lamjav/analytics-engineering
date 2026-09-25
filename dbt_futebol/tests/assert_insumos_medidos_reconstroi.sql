{{ config(tags=['guarda'], severity='error') }}
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
-- tag:guarda desde a AE#202. A condição que a AE#175 deixou escrita para ligar a tag é a
-- tabela estar no --select de TODO workflow que reconstrói os pais: o de odds entrou no DE#85
-- (16/09), o diário só no DE#105 (24/09). Até lá esta guarda ficava vermelha na suíte (FAIL
-- 2792/94/46 em 20, 23 e 24/09) porque o diário refazia o pai e deixava o filho defasado;
-- verde no diário e no de odds em 25/09 (AE#201).
--
-- AE#202: a chave de comparação inclui market e LINHA — no Handicap o mesmo (fixture,
-- outcome) tem várias linhas, cada uma com o seu conjunto de premissas. A linha entra como
-- texto (line_key, 'NONE' quando NULL) porque os mercados sem linha não a têm e NULL = NULL
-- não casaria no FULL OUTER JOIN.
--
-- AE#208: os mercados vêm de futebol_mercados_com_insumos_medidos(), a mesma lista que o
-- fact lê. Antes eram dois ramos escritos à mão aqui, que precisavam lembrar de crescer junto
-- com a UNION do fact.
{%- set mercados = futebol_mercados_com_insumos_medidos() %}

WITH origem AS (
{%- for m in mercados %}
    SELECT
        fixture_id,
        outcome,
        '{{ futebol_mercados_pontuados()[m.market_id] }}' AS market,
        {{ "COALESCE(CAST(line_value AS STRING), 'NONE')" if m.tem_linha else "'NONE'" }} AS line_key,
        TO_JSON_STRING(
            ARRAY(
                SELECT AS STRUCT premissa, insumo, valor
                FROM UNNEST(insumos_medidos)
                ORDER BY premissa, insumo
            )
        ) AS insumos_serializados
    FROM {{ ref(m.modelo) }}
{%- if not loop.last %}

    UNION ALL
{% endif %}
{%- endfor %}
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
    FROM {{ ref('fact_insumos_medidos') }}
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
