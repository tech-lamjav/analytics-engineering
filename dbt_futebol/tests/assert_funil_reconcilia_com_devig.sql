{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE RECONCILIAÇÃO DO FUNIL (#95, ADR 0011): o universo do `fact_value_funnel` é
-- exatamente o conjunto de candidatos do `int_futebol_odds_devig` nos cinco mercados
-- pontuados, nas quatro janelas. Nem uma linha a mais, nem uma a menos.
--
-- ⚠️ ELA LÊ A FONTE, NUNCA O PRÓPRIO FUNIL — e essa é a decisão inteira desta guarda.
-- A versão tentadora seria somar as rejeições do funil e comparar com o total do funil:
-- ela FECHA SEMPRE, porque as duas parcelas saem da mesma tabela. É a armadilha que a
-- costura B da task [F] já pagou uma vez: guarda que lê o próprio produto não é guarda,
-- é uma segunda cópia da exclusão.
--
-- O que ela pega, em cada direção:
--
--   · candidato do de-vig SEM linha no funil — algum join do modelo virou INNER sem
--     querer, ou um `WHERE` voltou a existir dentro de um ramo. É o modo de falha que a
--     tabela existe para impedir: a rejeição vira sumiço de novo, e o número publicado
--     parece certo;
--   · linha no funil SEM candidato no de-vig — fan-out. Os joins com as premissas e com
--     a corroboração são um-para-um por construção; se um deles duplicar (grão a montante
--     mudou, chave nova apareceu), toda taxa de rejeição do funil passa a ter denominador
--     inflado, e em silêncio.
--
-- A comparação é por CHAVE (EXCEPT DISTINCT nos dois sentidos), não por contagem: duas
-- contagens iguais convivem confortavelmente com um erro que tira uma linha de um lado e
-- põe outra do outro.
--
-- ⚠️ Ponto cego declarado, o de sempre (ADR 0005, subtask C4): até a C4 fechar, o job do
-- agendado devolve sucesso mesmo com esta guarda vermelha. Ela encurta o tempo até alguém
-- saber; não impede a tabela errada de ser publicada.

WITH fonte AS (
    SELECT
        fixture_id,
        {{ futebol_market_slug('market_id') }}          AS market,
        outcome_side                                    AS outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')    AS line_key,
        janela_usada                                    AS janela
    FROM {{ ref('int_futebol_odds_devig') }}
    WHERE market_id IN ({{ futebol_mercados_pontuados_ids() }})
),

funil AS (
    SELECT
        fixture_id,
        market,
        outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')    AS line_key,
        janela
    FROM {{ ref('fact_value_funnel') }}
)

SELECT
    *,
    'candidato do de-vig que não virou linha no funil — algum ramo voltou a filtrar (INNER JOIN ou WHERE), e a rejeição virou sumiço de novo' AS diagnostico
FROM (
    SELECT * FROM fonte
    EXCEPT DISTINCT
    SELECT * FROM funil
)

UNION ALL

SELECT
    *,
    'linha no funil sem candidato correspondente no de-vig — fan-out num dos joins do modelo; o denominador de toda taxa de rejeição está inflado' AS diagnostico
FROM (
    SELECT * FROM funil
    EXCEPT DISTINCT
    SELECT * FROM fonte
)
