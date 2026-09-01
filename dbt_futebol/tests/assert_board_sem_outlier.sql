{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DA BARREIRA DE OUTLIER (#104, virada #109): nenhuma linha publicada com
-- `pen_odd_outlier` TRUE — melhor odd >= 10% acima da média das outras casas, provável linha
-- mole ou erro de precificação.
--
-- `porta_outlier` entrou na conjunção de `passou_no_gate` na #109 (`NOT pen_odd_outlier`,
-- COALESCE por fora do NOT — penalidade ausente reprova a barreira, não aprova por acidente
-- de negação). `pen_odd_outlier` continua publicado no board (a migration 112 do app ainda
-- o lê para montar o aviso de risco na tela de detalhe), mas nenhuma linha PUBLICADA pode
-- carregá-lo TRUE — se carregar, a barreira que devia eliminá-la não segurou.
--
-- ⚠️ Espera-se VERMELHA contra dado de produção pré-virada. Sobe dentro da imagem e fica
-- verde no primeiro build pós-deploy.

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    pen_odd_outlier,
    'linha publicada com pen_odd_outlier TRUE (ou NULL) — a barreira de outlier (#104/#109) não segurou' AS diagnostico
FROM {{ ref('fact_value_opportunities') }}
WHERE pen_odd_outlier IS NOT FALSE
