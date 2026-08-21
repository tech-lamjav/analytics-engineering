
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
-- ⚠️ ELA COMPARA UMA TABELA CONTRA UMA VIEW VIVA, então ela é sensível ao ATRASO entre o
-- build e a execução dela. Odd coletada nesse intervalo aparece na fonte e ainda não no
-- funil, e a guarda acusa "candidato que não virou linha" sem que exista defeito. Medido
-- na validação da #96: 6 minutos de atraso bastaram para 84 linhas de UM fixture. No
-- workflow ela roda logo depois do modelo, então o intervalo é pequeno — mas quem rodar a
-- guarda à mão horas depois do último build vai ver isso, e a resposta é rodar o modelo
-- antes, não caçar defeito. Não é novidade desta entrega: no passo 1 a tabela também era
-- reconstruída a cada execução, com a mesma exposição.
--
-- ⚠️ Ponto cego declarado, o de sempre (ADR 0005, subtask C4): até a C4 fechar, o job do
-- agendado devolve sucesso mesmo com esta guarda vermelha. Ela encurta o tempo até alguém
-- saber; não impede a tabela errada de ser publicada.

WITH kickoff AS (
    -- O kickoff CORRENTE, lido do mesmo lugar que o modelo lê. Jogo adiado volta a ser
    -- gravável sozinho, porque o kickoff dele voltou para o futuro.
    -- prefixado porque o funil tem uma coluna `kickoff_utc` PRÓPRIA (a congelada), e as
    -- duas no mesmo escopo tornam a referência ambígua — que é exatamente o par que esta
    -- guarda não pode confundir.
    SELECT fixture_id, kickoff_utc AS _fx_kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

fonte AS (
    SELECT
        fixture_id,
        CASE market_id
        WHEN 1 THEN 'match_winner'
        WHEN 4 THEN 'asian_handicap'
        WHEN 5 THEN 'goals_over_under'
        WHEN 8 THEN 'btts'
        WHEN 12 THEN 'double_chance'
    END          AS market,
        outcome_side                                    AS outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')    AS line_key,
        janela_usada                                    AS janela
    FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    LEFT JOIN kickoff USING (fixture_id)
    WHERE market_id IN (1, 4, 5, 8, 12)
      -- O MESMO predicado que congela o modelo, lido do MESMO macro — nunca copiado.
      -- Aqui a divergência seria muda nos dois sentidos: mais frouxa e a guarda não
      -- acende, mais estrita e ela acende sem defeito.
      AND COALESCE(_fx_kickoff_utc > CURRENT_TIMESTAMP(), TRUE)
),

funil AS (
    SELECT
        fixture_id,
        market,
        outcome,
        -- a coluna GRAVADA, não recomputada: assim a comparação também VERIFICA a chave
        -- do merge, em vez de refazê-la e concordar consigo mesma.
        line_key,
        janela
    FROM `smartbetting-dados`.`futebol`.`fact_value_funnel`
    -- ⚠️ O KICKOFF VEM DE `fact_fixtures`, e NÃO da coluna da própria linha. O funil
    -- carrega o kickoff que valia quando a linha foi escrita pela última vez, e ele PARA
    -- de ser atualizado no apito — enquanto o lado da fonte, acima, lê o kickoff vivo.
    -- Dois relógios diferentes nos dois lados de um `EXCEPT` produzem vermelho eterno com
    -- o diagnóstico errado, e o caso é concreto: fixture que ainda não existia em
    -- `fact_fixtures` quando a odd foi coletada grava `kickoff_utc` NULL, entra aqui por
    -- fail-open PARA SEMPRE, e some da fonte no instante em que o fixture aparece com
    -- kickoff no passado — a guarda acusaria "fan-out num dos joins" para todo o sempre,
    -- sobre uma linha que não tem defeito nenhum.
    LEFT JOIN kickoff USING (fixture_id)
    WHERE COALESCE(_fx_kickoff_utc > CURRENT_TIMESTAMP(), TRUE)
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