
-- Reconciliação do spine: fact_fixture_stats faz INNER JOIN em fact_fixtures só p/ anexar
-- competition/season/date_utc e derivar team_side. Se um fixture existe no /statistics mas
-- FALTA em fact_fixtures, o INNER JOIN descarta as DUAS linhas do jogo de uma vez — e nem o
-- teste de "2 linhas por fixture" nem as sentinelas de pivot percebem (o jogo some do GROUP BY).
-- Isso encolhe a amostra do Poisson/value sem alarme. Este teste retorna (= falha) todo
-- fixture_id presente no stg de statistics e ausente do spine. severity warn: na prática o
-- spine é superset (mesmo dump /fixtures p/ as mesmas ligas/temporadas), mas um descompasso de
-- extração deve aparecer alto em vez de sumir. Promover a error quando a precedência
-- spine >= child estiver garantida na orquestração.
SELECT DISTINCT s.fixture_id
FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixture_statistics` s
LEFT JOIN `smartbetting-dados`.`futebol`.`fact_fixtures` f
    ON s.fixture_id = f.fixture_id
WHERE f.fixture_id IS NULL