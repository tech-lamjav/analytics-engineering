-- Sentinela de schema: o stg acessa campos aninhados do objeto /teams/statistics por nome
-- (src.fixtures.played.total, src.goals.`for`.total.total etc.). Se a API renomear um campo
-- aninhado, a coluna inteira vira NULL pra TODAS as linhas (tabela "verde mas vazia"). Este
-- teste falha alto nesse caso — played_total/goals_for_total não podem estar 100% NULL quando
-- há linhas. Passa em tabela vazia.
WITH agg AS (
    SELECT
        COUNT(*)              AS n_rows,
        COUNT(played_total)   AS n_played,
        COUNT(goals_for_total) AS n_goals_for
    FROM {{ ref('fact_team_season_stats') }}
)
SELECT *
FROM agg
WHERE n_rows > 0 AND (n_played = 0 OR n_goals_for = 0)
