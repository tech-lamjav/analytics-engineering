-- Garante a granularidade da subtask: cada fixture_id tem exatamente 2 linhas
-- (1 mandante + 1 visitante). Retorna linhas (= falha) para qualquer jogo com != 2.
SELECT
    fixture_id,
    COUNT(*) AS n_rows
FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats`
GROUP BY fixture_id
HAVING COUNT(*) <> 2