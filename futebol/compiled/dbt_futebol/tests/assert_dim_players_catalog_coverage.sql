-- Diagnóstico de cobertura do catálogo /players (a validação real do DoD da subtask 8:
-- "cada player_id tem entrada em dim_players"). NÃO é o teste relationships fact→dim
-- (que passa por construção depois do union em dim_players) — aqui o sinal é o TAMANHO
-- do gap: quantos jogadores entraram em campo mas faltam no catálogo (source='fixture_only').
-- Falha se o catálogo estiver muito incompleto (>30% fixture_only), indicando que o
-- extract_futebol_players precisa rodar/cobrir mais liga/temporada. Passa em tabela vazia.
WITH agg AS (
    SELECT
        COUNTIF(source = 'fixture_only') AS n_fixture_only,
        COUNT(*)                         AS n_total
    FROM `smartbetting-dados`.`futebol`.`dim_players`
)
SELECT *
FROM agg
WHERE n_total > 0 AND n_fixture_only > 0.30 * n_total