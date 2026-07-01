
-- Reconciliação do spine (gêmeo de assert_fixture_stats_reconciled p/ /fixtures/events):
-- fact_fixture_events faz INNER JOIN em fact_fixtures. Um fixture presente no /fixtures/events
-- mas ausente de fact_fixtures some inteiro (toda a linha do tempo do jogo), tirando sinal de
-- momentum/gols tardios sem nenhum teste falhar. Retorna (= falha) todo fixture_id presente no
-- stg e ausente do spine. severity warn (mesma justificativa do gêmeo).
SELECT DISTINCT e.fixture_id
FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixture_events` e
LEFT JOIN `smartbetting-dados`.`futebol`.`fact_fixtures` f
    ON e.fixture_id = f.fixture_id
WHERE f.fixture_id IS NULL