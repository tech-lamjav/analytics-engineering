
-- SENTINELA DA DECISÃO "O PREÇO SAI DA NOTA" (#103, ADR 0012).
--
-- Esta guarda não vigia dado: vigia a DECISÃO. Ela varre o texto que
-- `futebol_nota_contexto()` emite e fica vermelha se qualquer componente de preço
-- aparecer lá dentro. É o teste que impede a A1 de ser desfeita por acidente numa
-- entrega futura — alguém somando `pts_valor` de volta "só para o funil bater com o
-- board", ou reintroduzindo a corroboração ao mexer na composição.
--
-- ⚠️ POR QUE UMA GUARDA DE TEXTO, E NÃO DE DADOS. A pergunta "o preço entrou na nota?"
-- não tem resposta nos dados: se o preço entrar na composição, ele entra também na
-- recomposição da `assert_funil_nota_contexto_reconstroi` — as duas leem o MESMO macro —
-- e as duas fecham, verdes, sobre uma nota errada. Uma comparação estatística ("a nota
-- correlaciona com a odd?") seria pior: ela acende com o mundo, não com o código, porque
-- contexto e preço são correlacionados de verdade. O que se pode cobrar sem ambiguidade é
-- o TEXTO da composição, e é o que esta guarda cobra.
--
-- ⚠️ AS TRÊS JUNTAS COBREM O QUE NENHUMA COBRE SOZINHA, e é assim que elas foram
-- desenhadas:
--
--   · esta            — o preço não está DENTRO do macro;
--   · reconstrói      — o funil não FUGIU do macro (uma soma escrita à mão no modelo
--                       divergiria da recomposição e acenderia lá);
--   · o unit test     — a nota de contexto de dois candidatos com o MESMO contexto e
--     `funil_nota_de_contexto_ignora_o_preco`   preços opostos é a MESMA. É a única das
--                       três que olha um número.
--
-- ⚠️ NASCE EM ZERO (precedente da #33): a composição de hoje não contém componente de
-- preço nenhum, então a guarda devolve zero linha. Ela é INFALSIFICÁVEL em produção até
-- alguém mexer no macro — que é exatamente o dia em que se precisa dela. Foi dirigida ao
-- vermelho durante a implementação acrescentando `+ pts_valor` à composição: acusou o
-- componente, com o texto emitido no diagnóstico.
--
-- A lista dos componentes mora em `futebol_componentes_de_preco()`, ao lado da própria
-- composição, para que quem acrescentar um componente de preço ao Motor não tenha de
-- lembrar de um segundo arquivo. Ela é de SUBSTRING de propósito — ver o cabeçalho do
-- macro.

SELECT
    componente,
    'GREATEST(pts_premissas - penalidades_especificas_pts, 0)' AS composicao_emitida,
    'componente de PREÇO na composição da nota de contexto — a decisão da ADR 0012 foi desfeita (ou a lista de futebol_componentes_de_preco() precisa de uma exceção declarada por escrito)' AS diagnostico
-- ⚠️ O array é TIPADO (`ARRAY<STRING>[...]`), e não um `[...]` nu: no caminho verde ele
-- está VAZIO, e `UNNEST([])` não compila no BigQuery — não há de onde inferir o tipo do
-- elemento. Uma guarda cujo caminho verde é erro de sintaxe fica vermelha todo dia por
-- desenho, e guarda permanentemente vermelha morre ignorada.
FROM UNNEST(ARRAY<STRING>[
]) AS componente