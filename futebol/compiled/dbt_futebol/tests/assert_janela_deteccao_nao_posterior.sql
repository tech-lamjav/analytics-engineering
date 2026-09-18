
-- GUARDA DA INVARIANTE DA JANELA DE DETECÇÃO (#40, ADR 0004): a janela em que a linha foi
-- DETECTADA nunca é posterior à janela em que ela está sendo AVALIADA, e nunca é nula numa
-- linha publicada.
--
-- Hoje a invariante sai da construção do mart: só é publicada a linha que passou no gate na
-- janela corrente, então ela mesma é candidata ao FIRST_VALUE e não existe janela posterior a
-- ela na partição. A guarda existe porque "sai da construção" é precisamente o tipo de
-- garantia que um refactor futuro remove sem perceber — e o sintoma seria o board dizendo que
-- uma oportunidade nascida no fechamento já estava lá desde a véspera, que é uma mentira que
-- o apostador não tem como conferir.
--
-- As duas direções, e por que as duas importam:
--
--   · deteccao POSTERIOR à avaliada — a coluna passou a olhar para a frente. Seria o caso se
--     alguém trocasse a ordenação do FIRST_VALUE (ASC -> DESC) ou ordenasse pelo NOME da
--     janela: em ordem alfabética 'daily' < 't15m' < 't1h' < 't24h', e a t24h viraria a mais
--     tarde de todas;
--   · deteccao NULA — a linha foi publicada sem ter passado no gate em janela nenhuma, o que
--     só acontece se o filtro final e o cálculo da detecção pararem de falar do mesmo gate.
--
-- ⚠️ Ponto cego declarado: janela desconhecida tem prioridade 0 em futebol_janela_prioridade()
-- e, comparada com uma janela conhecida, satisfaz "não é posterior" trivialmente. É o mesmo
-- ponto cego que a #37 registrou no macro, e quem previne de verdade é o accepted_values de
-- `fact_odds_snapshot.collection_window`, a montante — janela nova só chega aqui se antes
-- existir lá.

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    janela_usada,
    janela_deteccao,
    CASE
        WHEN janela_deteccao IS NULL
            THEN 'linha publicada sem janela de detecção — o filtro final e o cálculo da detecção deixaram de usar o mesmo gate'
        ELSE 'janela de detecção posterior à janela avaliada — a coluna passou a olhar para a frente (ordenação do FIRST_VALUE invertida ou por nome?)'
    END AS diagnostico
FROM `smartbetting-dados`.`futebol`.`fact_value_opportunities`
WHERE janela_deteccao IS NULL
   OR (CASE janela_deteccao
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END)
      > (CASE janela_usada
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END)
ORDER BY fixture_id, market, outcome, line_value