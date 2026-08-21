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
-- ⚠️ ESCOPADA AO QUE AINDA É GRAVÁVEL (#96). Desde o congelamento no apito (ADR 0011) as
-- duas tabelas deixaram de ter o mesmo universo, e a igualdade sem escopo passou a ser
-- falsa por construção nos DOIS sentidos:
--
--   · o funil guarda história que a fonte não guarda. Ele nunca expurga (~45 mil
--     linhas/mês, para sempre); o de-vig só emite enquanto a coleta emite aquele fixture.
--     No primeiro dia em que a fonte soltar um jogo velho, a guarda sem escopo acenderia
--     vermelha POR ESTAR CERTA — e guarda permanentemente vermelha morre ignorada;
--   · a fonte pode passar a emitir candidato de jogo já apitado, e o funil — corretamente
--     — não o grava mais. Cobrar essa linha seria cobrar a violação do congelamento.
--
-- O escopo é, então, o conjunto de que o modelo é responsável NESTA execução: candidato
-- cujo fixture ainda não começou (ou cujo kickoff se desconhece, que é gravável para
-- sempre por fail-open). Dentro dele a igualdade continua exata e os dois modos de falha
-- acima continuam cobertos.
--
-- ⚠️ O preço do escopo, dito em voz alta: a história JÁ CONGELADA sai da conferência. Uma
-- linha que suma de um dia encerrado não acende aqui — acende em
-- `assert_funil_imutavel_por_dia_de_kickoff`, que é a guarda escrita para essa metade.
--
-- ⚠️ Ponto cego declarado, o de sempre (ADR 0005, subtask C4): até a C4 fechar, o job do
-- agendado devolve sucesso mesmo com esta guarda vermelha. Ela encurta o tempo até alguém
-- saber; não impede a tabela errada de ser publicada.

WITH kickoff AS (
    -- O kickoff CORRENTE, lido do mesmo lugar que o modelo lê. Jogo adiado volta a ser
    -- gravável sozinho, porque o kickoff dele voltou para o futuro.
    SELECT fixture_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

fonte AS (
    SELECT
        fixture_id,
        {{ futebol_market_slug('market_id') }}          AS market,
        outcome_side                                    AS outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')    AS line_key,
        janela_usada                                    AS janela
    FROM {{ ref('int_futebol_odds_devig') }}
    LEFT JOIN kickoff USING (fixture_id)
    WHERE market_id IN ({{ futebol_mercados_pontuados_ids() }})
      -- O MESMO predicado que congela o modelo, COALESCE e tudo: kickoff no futuro, ou
      -- fixture que `fact_fixtures` não conhece (fail-open — o modelo grava essa linha
      -- para sempre, então a fonte tem de cobrá-la para sempre). Copiado aqui de
      -- propósito e não extraído para macro: são três linhas e o macro esconderia
      -- justamente o que esta guarda precisa deixar visível.
      AND COALESCE(kickoff_utc > CURRENT_TIMESTAMP(), TRUE)
),

funil AS (
    SELECT
        fixture_id,
        market,
        outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')    AS line_key,
        janela
    FROM {{ ref('fact_value_funnel') }}
    -- O funil carrega o kickoff, então aqui o predicado se lê direto da própria linha.
    WHERE COALESCE(kickoff_utc > CURRENT_TIMESTAMP(), TRUE)
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
