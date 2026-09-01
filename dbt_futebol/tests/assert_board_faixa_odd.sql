{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DA BARREIRA DE FAIXA DE ODD (#104, virada #109): nenhuma linha publicada com
-- `best_odd` fora da faixa do seu mercado — [1,50; 4,00] nos quatro mercados gerais,
-- [1,25; 2,00] na Dupla Chance, fronteiras INCLUSIVAS nas duas pontas.
--
-- `porta_faixa_odd` entrou na conjunção de `passou_no_gate` na #109. A garantia já sai da
-- construção do funil (NULL-safe, COALESCE(..., FALSE) reprova insumo ausente); esta guarda
-- é a rede de segurança contra um refactor futuro que troque a conjunção ou faça o board
-- voltar a recompor o gate em vez de ler `passou_no_gate` gravado.
--
-- Os limites são os mesmos `var` do funil (faixa_odd_min=1.50, faixa_odd_max=4.00,
-- faixa_odd_dc_min=1.25, faixa_odd_dc_max=2.00) — declarados aqui de novo, e não lidos de
-- volta do funil, porque a guarda tem de poder acusar mesmo se o var mudar só de um lado.
--
-- ⚠️ Espera-se VERMELHA contra dado de produção pré-virada. Sobe dentro da imagem e fica
-- verde no primeiro build pós-deploy.

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    best_odd,
    'linha publicada com best_odd fora da faixa do mercado — a barreira de faixa de odd (#104/#109) não segurou' AS diagnostico
FROM {{ ref('fact_value_opportunities') }}
WHERE NOT (
    best_odd >= CASE WHEN market = 'double_chance' THEN {{ var('faixa_odd_dc_min', 1.25) }}
                     ELSE {{ var('faixa_odd_min', 1.50) }} END
    AND
    best_odd <= CASE WHEN market = 'double_chance' THEN {{ var('faixa_odd_dc_max', 2.00) }}
                     ELSE {{ var('faixa_odd_max', 4.00) }} END
) OR best_odd IS NULL
