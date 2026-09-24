

-- ============================================================================
-- O FLIP (#97, A7-3): o board passa a ser o que ele sempre foi conceitualmente e nunca foi
-- no código — o FUNIL FILTRADO.
--
-- O que saiu daqui: os cinco ramos por mercado (joined_1x2/_ou/_ah/_btts/_dc), o de-vig em
-- todas as janelas, a corroboração, a montagem do score e a CTE `avaliadas` que
-- reconstruía o gate. Tudo isso vive no `fact_value_funnel` desde a #95, e mantê-lo em
-- dois lugares era a duplicação que a `assert_funil_paridade_com_board` vigiava. A guarda
-- é aposentada NESTE MESMO COMMIT, como a própria ADR 0011 mandou: depois do flip ela
-- compara a tabela consigo mesma.
--
-- ⚠️ O FILTRO INGÊNUO ESTARIA ERRADO, e é a armadilha central deste ticket:
-- `WHERE janela_e_corrente AND passou_no_gate` NÃO BASTA. O funil guarda jogo encerrado de
-- propósito (ADR 0011) — é ele que responde quanto rendeu a faixa descartada —, então um
-- board filtrado só por essas duas colunas voltaria a emitir jogo velho para sempre,
-- reintroduzindo pela porta dos fundos o defeito de 121 linhas com 2 jogos futuros que a
-- #85 acabou de consertar. A JUNÇÃO COM O STATUS VAI JUNTO NO FLIP, e é a terceira
-- condição do WHERE final.
-- ============================================================================

WITH funil AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`fact_value_funnel`
),

-- ============================================================================
-- O ÚNICO INSUMO QUE NÃO VEM DO FUNIL — e é decisão da ADR 0011, não esquecimento.
--
-- `evidencias[]` e `avisos_especificos[]` ficaram fora do funil por serem derivados e
-- reconstruíveis (e porque ARRAY<STRING> não atravessa o sync). São strings de EXIBIÇÃO:
-- nenhum veredito sai daqui, nenhuma porta é avaliada aqui, e o score não olha para isto.
--
-- Os cinco modelos entram unidos num grão só — (fixture_id, market, outcome, line_key) —,
-- com EXATAMENTE as chaves que os cinco ramos antigos usavam: 1X2, BTTS e Dupla Chance
-- casam por (fixture, saída) e têm `line_value` NULL; Gols O/U e Handicap casam também
-- pela linha, sempre via `line_key` (STRING, NULL-safe), nunca por igualdade de FLOAT.
--
-- O `market` vem de `futebol_mercados_pontuados()`, o mesmo mapa que o funil usa, para que
-- o vocabulário dos dois lados não possa divergir em silêncio.
-- ============================================================================
-- ⚠️ `tem_linha` não é estilo: 1X2, Ambos Marcam e Dupla Chance **não têm a coluna
-- `line_value`** nos seus modelos (o mercado não tem linha), então referenciá-la ali nem
-- compila. Para eles o `line_key` é o literal 'NONE' — exatamente o que o funil grava,
-- porque lá o `COALESCE(..., 'NONE')` cai no mesmo valor. É a mesma assimetria que os cinco
-- ramos antigos expressavam ao juntar três deles sem predicado de linha.
premissas AS (
    
    
    SELECT
        fixture_id,
        'match_winner'          AS market,
        outcome,
        'NONE'                                                   AS line_key,
        evidencias                                               AS evidencias_premissas,
        avisos                                                   AS avisos_especificos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
    UNION ALL
    
    SELECT
        fixture_id,
        'goals_over_under'          AS market,
        outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')             AS line_key,
        evidencias                                               AS evidencias_premissas,
        avisos                                                   AS avisos_especificos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou`
    UNION ALL
    
    SELECT
        fixture_id,
        'asian_handicap'          AS market,
        outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')             AS line_key,
        evidencias                                               AS evidencias_premissas,
        avisos                                                   AS avisos_especificos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
    UNION ALL
    
    SELECT
        fixture_id,
        'btts'          AS market,
        outcome,
        'NONE'                                                   AS line_key,
        evidencias                                               AS evidencias_premissas,
        avisos                                                   AS avisos_especificos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts`
    UNION ALL
    
    SELECT
        fixture_id,
        'double_chance'          AS market,
        outcome,
        'NONE'                                                   AS line_key,
        evidencias                                               AS evidencias_premissas,
        avisos                                                   AS avisos_especificos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
    
    
),

-- O EXPURGO DO BOARD (#85, ADR 0009): o único uso de `fact_fixtures` neste mart, e ele
-- serve só ao filtro final.
--
-- ⚠️ Lido de `fact_fixtures` e NUNCA do `kickoff_utc` que o funil grava: aquela coluna
-- congela no apito por construção (ADR 0011, D10) e o expurgo precisa do relógio corrente.
-- É a mesma razão pela qual a guarda de paridade lia daqui, e não da coluna da linha.
--
-- As duas colunas vêm com prefixo `_fx_` por necessidade, não por estilo: `fact_fixtures`
-- também tem `competition` e `season`, e a lista final referencia as duas sem qualificar.
fixtures AS (
    SELECT
        fixture_id,
        status_short AS _fx_status_short,
        kickoff_utc  AS _fx_kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- ============================================================================
-- A JANELA DE DETECÇÃO (#40, ADR 0004): a janela mais cedo, entre as coletadas para esta
-- linha, em que ela passou no gate. Diz há quanto tempo a oportunidade está no board.
--
-- ⚠️ A EXPRESSÃO NÃO MUDOU, e a população sobre a qual ela roda também não. Antes do flip
-- o mart abria o de-vig em todas as janelas e avaliava (linha × janela) só para poder
-- calcular esta coluna. O funil JÁ É essa população — uma linha por (candidato, janela),
-- com o `passou_no_gate` daquela janela —, então o FIRST_VALUE encontra exatamente as
-- mesmas candidatas. O que sumiu foi o custo de reavaliar o gate 4× por linha, não o
-- conceito.
--
-- É calculada ANTES do filtro final de propósito: a janela que detectou não é (quase
-- nunca) a janela publicada, e filtrar primeiro apagaria justamente as linhas de onde ela
-- sai. A ordenação é por `janela_prioridade`, nunca pelo nome ('daily' < 't15m' em ordem
-- alfabética diria o contrário).
--
-- INVARIANTE: janela_deteccao nunca é posterior à janela publicada. Sai de graça da
-- construção — a linha publicada passou no gate na janela corrente, então ela mesma é
-- candidata ao FIRST_VALUE. A guarda assert_janela_deteccao_nao_posterior mede isso em
-- produção mesmo assim, porque "sai da construção" é o tipo de garantia que um refactor
-- futuro remove sem perceber. Este commit É um desses refactors.
-- ============================================================================
com_deteccao AS (
    SELECT
        *,
        FIRST_VALUE(IF(passou_no_gate, janela, NULL) IGNORE NULLS) OVER (
            PARTITION BY fixture_id, market, outcome, line_key
            ORDER BY janela_prioridade
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS janela_deteccao
    FROM funil
)

SELECT
    f.fixture_id,
    f.market,
    f.outcome,
    f.line_value,
    f.competition,
    f.season,

    f.edge,
    f.pts_premissas,
    -- quantas premissas do mercado se aplicavam a esta linha, não acenderam, e não acenderam
    -- por falta de insumo (#41). Não entra na conta do score: é o que o score NÃO pôde levar
    -- em conta. Filtrar por ela é o que permite medir a base por completude.
    f.premissas_sem_dado,
    -- ⚠️ #109: penalidade publicada passa a ser só a de CONTEXTO — a mesma parcela que
    -- `futebol_nota_contexto()` subtrai (pick_empate/desfalque_proprio/linha_extrema/
    -- handicap_alto). `penalidades_globais_pts` (as quatro de odd) sai da soma publicada
    -- aqui porque saiu do Score; os quatro flags continuam publicados abaixo, sem compor
    -- nada — são leitura de risco de preço, lidas pelo app na tela de detalhe.
    f.penalidades_especificas_pts AS penalidades,
    -- ⚠️ #109: o Score publicado passa a SER a nota normalizada do funil — a mesma
    -- aritmética, um nome em cada tabela (glossário, CONTEXT.md). Não é uma segunda
    -- fórmula: `score_normalizado` já é 0–100, absoluto, sem preço.
    f.score_normalizado AS score,
    -- ⚠️ #109: fronteiras da #107 (PR #133) eram 25/55; trocadas para 30/60 por decisão
    -- do PM (01/09, comentário na #109) — não é leitura de evidência nova, a #107 já
    -- tinha medido que nenhum par da grade discrimina Alta de Baixa além de 1 EP. Baixa
    -- < 30 <= Média < 60 <= Alta, fronteira na faixa de cima nas duas. 'Baixa' passa a
    -- materializar: a régua de nota saiu do gate (decisão do PM de 20/08), então a faixa
    -- é rótulo, não mais sentinela de corte.
    CASE
        WHEN f.score_normalizado IS NULL THEN NULL
        WHEN f.score_normalizado >= 60   THEN 'Alta'
        WHEN f.score_normalizado >= 30   THEN 'Média'
        ELSE 'Baixa'
    END AS faixa,
    -- técnica, nunca exibida ao usuário (comment da migration 112 do app). 'legacy' é o
    -- default que a migration carimba nas linhas já sincronizadas antes deste deploy;
    -- toda linha que este mart materializa a partir daqui é 'contexto_v1'.
    'contexto_v1' AS score_versao,

    -- "por quê": só premissas que dispararam. ⚠️ #109: a corroboração saiu — ela não soma
    -- mais ao Score, então as duas bullets "+7"/"+8" (modelo da API, linha sharp) mentiam
    -- pontos que deixaram de existir. `modelo_api_concorda`/`linha_sharp_confirma`
    -- continuam publicadas abaixo, informativas, para quem quiser o dado cru.
    p.evidencias_premissas AS evidencias,

    -- avisos: penalidades específicas do mercado + cegueira. ⚠️ #109: os quatro avisos de
    -- odd (outlier/poucas casas/longshot/juice) SAEM daqui — os pen_odd_* continuam
    -- publicados como coluna (a RPC do app monta o próprio aviso a partir deles via
    -- `futebol_copy`), mas o texto fixo com pontos entre parênteses (−30/−12/−15/−10)
    -- descreveria um desconto que não acontece mais no Score.
    ARRAY_CONCAT(
        p.avisos_especificos,
        ARRAY(SELECT y FROM UNNEST([
            IF(f.premissas_sem_dado > 0,
               FORMAT('⚠ %d premissa(s) sem dado — a nota está incompleta, não contrária',
                      f.premissas_sem_dado), NULL)
        ]) AS y WHERE y IS NOT NULL)
    ) AS avisos,

    -- contexto de odds
    f.best_odd,
    f.best_book,
    f.avg_odd,
    f.n_casas,
    f.prob_justa_fechamento,
    f.valor_fonte,
    -- ⚠️ o funil chama de `janela`; o board publica como `janela_usada` desde sempre.
    -- Renomear a coluna do board seria mudança de contrato de serving por estética.
    f.janela                        AS janela_usada,
    -- #40: a janela mais cedo em que esta linha passou no gate. Igual a janela_usada
    -- quando a oportunidade nasceu na janela corrente; mais cedo quando ela já estava
    -- no board antes. Nunca posterior a janela_usada.
    f.janela_deteccao,

    -- componentes (transparência/debug). ⚠️ #109: `penalidades_globais_pts` SAI — era o
    -- agregado das quatro de odd, que deixaram de compor o Score publicado (ver
    -- `penalidades` acima). Os quatro flags abaixo (#87) FICAM: a migration 112 do app
    -- (`get_futebol_fixture_value`) ainda os lê para montar o aviso de risco de preço na
    -- tela de detalhe — dropá-los quebraria essa RPC.
    f.pen_odd_outlier,
    f.pen_poucas_casas,
    f.pen_odd_longshot,
    f.pen_odd_juice,
    f.penalidades_especificas_pts,
    f.modelo_api_concorda,
    f.linha_sharp_confirma,
    f.pin_n_outcomes,
    f.is_half_line,
    -- #2: para rankear por VALOR use `edge` (o score/faixa é índice de CONFIANÇA, não monotônico
    -- no edge — um bet de 1% de edge pode ter score maior que um de 6%). Sem coluna ev_rank dedicada.

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM com_deteccao f
-- LEFT, nunca INNER: linha publicada cuja premissa não casasse sumiria do board em
-- silêncio — a perda muda que a ADR 0009 existe para impedir. Com LEFT ela fica, e o que
-- aparece é `evidencias` vazio, que é visível.
LEFT JOIN premissas p
    ON  p.fixture_id = f.fixture_id
    AND p.market     = f.market
    AND p.outcome    = f.outcome
    AND p.line_key   = f.line_key
-- LEFT, nunca INNER (#85, ADR 0009 + ADR 0003). Fixture que não existe em `fact_fixtures`
-- não deve sumir do board: sumir seria a perda silenciosa que a ADR 0009 existe para
-- impedir. O predicado do expurgo devolve NULL nesse caso e o `COALESCE(..., FALSE)` abaixo
-- deixa a linha passar — e a guarda 1 acende vermelho com diagnóstico próprio, que é o
-- caminho certo para dado faltante: diagnosticar, não eliminar.
-- ⚠️ `ON`, e não `USING (fixture_id)`: depois do join com `premissas` existem DOIS
-- `fixture_id` do lado esquerdo e o `USING` fica ambíguo. O antigo usava `USING` porque
-- havia uma relação só à esquerda.
LEFT JOIN fixtures fx
    ON fx.fixture_id = f.fixture_id
-- A REDUÇÃO A UMA LINHA POR (fixture, mercado, saída, linha). As duas primeiras condições
-- respondem coisas diferentes e as duas são necessárias:
--   janela_e_corrente — publica o preço que o usuário consegue pegar AGORA (e é o que
--                       garante uma linha só: o flag vem de um MAX por (fixture, mercado,
--                       linha) sobre o de-vig cru);
--   passou_no_gate    — a oportunidade tem de valer NA janela corrente. Ter valido em t24h
--                       e não valer mais em t15m é motivo para sair do board, não para
--                       ficar nele com carimbo antigo (ADR 0004).
--
-- ⚠️ `passou_no_gate` é a COLUNA GRAVADA no funil, lida e nunca recomposta a partir das
-- portas. Recompô-la aqui recriaria a segunda cópia da aritmética que este ticket veio
-- matar. As três barreiras de preço da #104 (liquidez estrita, outlier, faixa de odd)
-- entraram na conjunção gravada na #109 — este board já as herda por ler `passou_no_gate`,
-- sem precisar saber o nome de nenhuma delas.
WHERE f.janela_e_corrente
  AND f.passou_no_gate
  -- O BOARD É A JANELA DO QUE AINDA DÁ PARA APOSTAR (#85, ADR 0009). É a condição que o
  -- filtro ingênuo esqueceria, e sem ela o funil — que guarda jogo encerrado de propósito —
  -- devolveria jogo velho ao board para sempre. O predicado mora em
  -- `macros/futebol_expurgo.sql`, num lugar só, porque a guarda 1 o espelha para provar que
  -- o expurgo aconteceu — e predicado copiado é predicado que diverge.
  --
  -- Nada é apagado: o mart é reconstruído do zero e o `fact_value_opportunities_hist` fecha
  -- e guarda a versão pelo `invalidate_hard_deletes` do snapshot. Sair do board é deixar de
  -- ser emitida, não deixar de ter existido.
  AND NOT COALESCE(
        (
        fx._fx_status_short IN ('FT', 'AET', 'PEN', 'CANC', 'ABD', 'AWD', 'WO', '1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE')
        OR (
            TIMESTAMP_ADD(fx._fx_kickoff_utc, INTERVAL 24 HOUR)
                < CURRENT_TIMESTAMP()
            -- COALESCE, e não `fx._fx_status_short NOT IN (...)` direto: status nulo tem de
            -- ser alcançado pela carência, não escapar dela por NULL. Ver o cabeçalho.
            AND COALESCE(fx._fx_status_short, '') NOT IN ('PST', 'SUSP', 'INT')
        )
    ),
        FALSE
      )