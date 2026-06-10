-- Sentinela de schema: o stg acessa campos aninhados do struct statistics por nome
-- (src.statistics.games.minutes etc.). Se a API renomear um campo aninhado, a coluna
-- inteira vira NULL pra TODAS as linhas (tabela "verde mas vazia"). Este teste falha
-- alto nesse caso — minutes não pode estar 100% NULL quando há linhas. Passa em tabela vazia.
WITH agg AS (
    SELECT
        COUNT(*)       AS n_rows,
        COUNT(minutes) AS n_minutes
    FROM {{ ref('fact_fixture_player_stats') }}
)
SELECT *
FROM agg
WHERE n_rows > 0 AND n_minutes = 0
