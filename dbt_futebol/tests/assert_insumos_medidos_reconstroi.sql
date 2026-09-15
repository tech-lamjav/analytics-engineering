{{ config(severity='error') }}
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
-- ⚠️ SEM tag:guarda de propósito — ver aviso no topo de models/marts/fact_insumos_medidos.sql.
-- A tabela ainda não está no --select de workflow_futebol_odds.yml (ticket separado,
-- data-engineering); marcar esta guarda agora faria a fase agendada de
-- `dbt test --select tag:guarda` do PRD quebrar contra uma tabela que o `dbt run` daquele
-- workflow nunca constrói. Adicionar a tag junto do PR que adicionar o modelo ao selector.

WITH origem AS (
    SELECT
        fixture_id,
        outcome,
        TO_JSON_STRING(
            ARRAY(
                SELECT AS STRUCT premissa, insumo, valor
                FROM UNNEST(insumos_medidos)
                ORDER BY premissa, insumo
            )
        ) AS insumos_serializados
    FROM {{ ref('int_futebol_premissas_1x2') }}
),

achatado AS (
    SELECT
        fixture_id,
        outcome,
        TO_JSON_STRING(
            ARRAY_AGG(STRUCT(premissa, insumo, valor) ORDER BY premissa, insumo)
        ) AS insumos_serializados
    FROM {{ ref('fact_insumos_medidos') }}
    GROUP BY fixture_id, outcome
)

SELECT
    COALESCE(o.fixture_id, a.fixture_id) AS fixture_id,
    COALESCE(o.outcome, a.outcome) AS outcome,
    COALESCE(o.insumos_serializados, '[]') AS insumos_medidos_origem,
    COALESCE(a.insumos_serializados, '[]') AS insumos_medidos_achatado
FROM origem AS o
FULL OUTER JOIN achatado AS a
    ON o.fixture_id = a.fixture_id
   AND o.outcome = a.outcome
WHERE COALESCE(o.insumos_serializados, '[]') != COALESCE(a.insumos_serializados, '[]')
