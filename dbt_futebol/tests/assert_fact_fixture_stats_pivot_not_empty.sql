-- Sentinela do pivot: se a string de `type` da API mudar, a coluna pivotada vira NULL pra
-- TODAS as linhas (tabela "verde mas vazia"). Este teste falha alto nesse caso. Passa em
-- tabela vazia.
--   • total_shots existe em TODO jogo finalizado (qualquer liga/temporada) -> checagem GLOBAL.
--   • expected_goals/goals_prevented (os campos que ALIMENTAM o value betting via xG) só são
--     fornecidos pela API em jogos recentes -> a sentinela do xG é ESCOPADA a brasileirao +
--     últimos 200 dias (e exige amostra >=10) p/ falhar alto num rename de label SEM
--     falso-positivar em backfill antigo / competição sem xG (ex.: Copa do Mundo).
WITH agg AS (
    SELECT
        COUNT(*)            AS n_rows,
        COUNT(total_shots)  AS n_total_shots,
        COUNTIF(competition = 'brasileirao'
                AND date_utc >= DATE_SUB(CURRENT_DATE(), INTERVAL 200 DAY))                      AS n_rows_xg_scope,
        COUNTIF(competition = 'brasileirao'
                AND date_utc >= DATE_SUB(CURRENT_DATE(), INTERVAL 200 DAY)
                AND expected_goals  IS NOT NULL)                                                 AS n_xg,
        COUNTIF(competition = 'brasileirao'
                AND date_utc >= DATE_SUB(CURRENT_DATE(), INTERVAL 200 DAY)
                AND goals_prevented IS NOT NULL)                                                 AS n_goals_prevented
    FROM {{ ref('fact_fixture_stats') }}
)
SELECT *
FROM agg
WHERE (n_rows > 0 AND n_total_shots = 0)
   OR (n_rows_xg_scope >= 10 AND n_xg = 0)
   OR (n_rows_xg_scope >= 10 AND n_goals_prevented = 0)
