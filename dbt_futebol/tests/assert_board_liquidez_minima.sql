{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DA BARREIRA DE LIQUIDEZ (#104, virada #109): nenhuma linha publicada com menos de
-- `liquidez_min_casas` (4) casas cobrindo o mercado.
--
-- `porta_liquidez_estrita` entrou na conjunção de `passou_no_gate` na #109, no lugar da
-- antiga `porta_liquidez` (>= 3). A garantia já sai da construção do funil — ela é
-- NULL-safe (COALESCE(..., FALSE) reprova insumo ausente) e está na conjunção lida por
-- `fact_value_opportunities`. Esta guarda existe pela mesma razão que
-- `assert_janela_deteccao_nao_posterior`: "sai da construção" é o tipo de garantia que um
-- refactor futuro remove sem perceber — trocar a conjunção do funil, ou fazer o board voltar
-- a recompor o gate em vez de ler `passou_no_gate`, são os dois jeitos de quebrar isto em
-- silêncio.
--
-- ⚠️ Espera-se VERMELHA contra dado de produção pré-virada (o board hoje tem linha de
-- exatamente 3 casas). Ela sobe dentro da imagem e fica verde no primeiro build pós-deploy,
-- quando o board novo publica.

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    n_casas,
    'linha publicada com n_casas < 4 — a barreira de liquidez estrita (#104/#109) não segurou' AS diagnostico
FROM {{ ref('fact_value_opportunities') }}
WHERE n_casas < 4 OR n_casas IS NULL
