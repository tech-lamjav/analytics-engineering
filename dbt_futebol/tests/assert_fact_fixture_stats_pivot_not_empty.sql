-- Sentinela do pivot: se a string de `type` da API mudar, a coluna pivotada vira
-- NULL pra TODAS as linhas (tabela "verde mas vazia"). Este teste falha alto nesse
-- caso — total_shots não pode estar 100% NULL quando há linhas. Passa em tabela vazia.
WITH agg AS (
    SELECT
        COUNT(*)            AS n_rows,
        COUNT(total_shots)  AS n_total_shots
    FROM {{ ref('fact_fixture_stats') }}
)
SELECT *
FROM agg
WHERE n_rows > 0 AND n_total_shots = 0
