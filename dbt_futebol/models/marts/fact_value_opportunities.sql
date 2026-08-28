{{ config(
    materialized='table',
    cluster_by=['competition', 'fixture_id'],
    description='Mart de saída do Motor de Score de Confiabilidade (value bet futebol). ⚠️ DESDE A #97 (A7-3, ADR 0011) ESTE MODELO É O FUNIL FILTRADO, e não uma segunda derivação do Motor: ele lê `fact_value_funnel` e aplica, na leitura, `janela_e_corrente AND passou_no_gate` mais a regra de expurgo da #85. A lógica de porta passou a existir NUM LUGAR SÓ — os cinco ramos por mercado saíram daqui, e com eles a duplicação que a `assert_funil_paridade_com_board` existia para vigiar (guarda APOSENTADA no mesmo commit: depois do flip ela compara a tabela consigo mesma, e guarda que não pode falhar é ruído com cara de cobertura). O GATE NÃO É RECOMPOSTO AQUI: lê-se a coluna `passou_no_gate` GRAVADA no funil, nunca a conjunção das portas — recompô-la seria recriar a segunda cópia que este ticket veio matar, e é também o que mantém as três barreiras de preço da #104 (porta_liquidez_estrita/porta_outlier/porta_faixa_odd) FORA do board até a virada (#109), já que elas estão fora da conjunção gravada. O QUE AINDA NÃO VEM DO FUNIL, e por decisão: `evidencias[]` e `avisos[]`. A ADR 0011 deixou os dois fora do funil por serem derivados e reconstruíveis, então o mart mantém UM join com os cinco modelos de premissas — unidos em `premissas`, com o mesmo grão (fixture, mercado, saída, line_key) e as mesmas chaves dos cinco ramos antigos — só para as duas arrays de exibição. Nenhum veredito sai daí. 1 linha por (fixture_id, market, outcome, line_value) que PASSA no gate. Score 0-100 = clamp(PTS_VALOR + PTS_PREMISSAS + PTS_CORROBORACAO − PENALIDADES), calculado no funil. faixa Alta(>=60)/Média(40-59)/Baixa; abaixo de 40 não vira oportunidade porque a porta de nota já reprovou. evidencias[] = o "por quê" (premissas + corroboração); avisos[] = red flags. Long por `market`: 1X2 (1) + Gols O/U (5) + Handicap asiático (4) + Ambos Marcam (8) + Dupla Chance (12, saídas 1X/X2). line_value é NULL no 1X2/BTTS/DC, a linha L no O/U e o handicap (ótica do mandante) no AH. valor_fonte = pinnacle ou consenso (rotular como estimativa no front). Contador de cegueira (#41, ADR 0003): premissas_sem_dado diz QUANTAS premissas aplicáveis àquela linha não puderam ser avaliadas por falta de insumo; não desconta nada e sai como aviso SEM pontos entre parênteses. JANELA DE DETECÇÃO (#40, ADR 0004): janela_deteccao é a janela mais cedo (daily<t24h<t1h<t15m) em que ESTA linha passou no gate, calculada agora sobre as quatro janelas DO FUNIL — que é a mesma população de (linha × janela) que o mart avaliava à mão antes, e por isso a coluna não muda de sentido. Nunca posterior a janela_usada (guarda assert_janela_deteccao_nao_posterior). Linha que passou numa janela cedo e não passa na corrente NÃO aparece no board: preço que o usuário não consegue mais pegar não é oportunidade, e o histórico do que já foi anunciado vive no snapshot fact_value_opportunities_hist. PARCELAS DA PENALIDADE GLOBAL (#87): as quatro flags pen_odd_* continuam publicadas, agora lidas do funil. EXPURGO DO BOARD (#85, ADR 0009): o mart é a janela do que AINDA DÁ PARA APOSTAR — junta fact_fixtures e não emite linha de jogo com status terminal nem ao vivo, com rede de segurança em kickoff + var expurgo_carencia_horas (24). PST/SUSP/INT SOBREVIVEM. ⚠️ O expurgo é lido de `fact_fixtures`, NUNCA do `kickoff_utc` gravado no funil: aquela coluna congela no apito e o expurgo precisa do relógio corrente. NENHUMA COLUNA NOVA sai daqui — mesmo payload de antes do flip, mesma ordem, mesmos tipos: sem migração no Postgres, sem tocar RPC, `check_schema_parity` intacto. O funil segue sem sincronizar.'
) }}

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
    SELECT * FROM {{ ref('fact_value_funnel') }}
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
    {% set ramos = [
        (1,  'int_futebol_premissas_1x2',  false),
        (5,  'int_futebol_premissas_ou',   true),
        (4,  'int_futebol_premissas_ah',   true),
        (8,  'int_futebol_premissas_btts', false),
        (12, 'int_futebol_premissas_dc',   false)
    ] %}
    {% for market_id, modelo, tem_linha in ramos %}
    SELECT
        fixture_id,
        '{{ futebol_mercados_pontuados()[market_id] }}'          AS market,
        outcome,
        {% if tem_linha -%}
        COALESCE(CAST(line_value AS STRING), 'NONE')             AS line_key,
        {%- else -%}
        'NONE'                                                   AS line_key,
        {%- endif %}
        evidencias                                               AS evidencias_premissas,
        avisos                                                   AS avisos_especificos
    FROM {{ ref(modelo) }}
    {% if not loop.last %}UNION ALL{% endif %}
    {% endfor %}
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
    FROM {{ ref('fact_fixtures') }}
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
    f.pts_valor,
    f.pts_premissas,
    -- quantas premissas do mercado se aplicavam a esta linha, não acenderam, e não acenderam
    -- por falta de insumo (#41). Não entra na conta do score: é o que o score NÃO pôde levar
    -- em conta. Filtrar por ela é o que permite medir a base por completude.
    f.premissas_sem_dado,
    f.pts_corroboracao,
    f.penalidades,
    f.score,
    CASE
        WHEN f.score >= 60 THEN 'Alta'
        WHEN f.score >= 40 THEN 'Média'
        ELSE 'Baixa'
    END AS faixa,

    -- "por quê": premissas que dispararam + corroboração confirmada.
    ARRAY_CONCAT(
        p.evidencias_premissas,
        ARRAY(SELECT x FROM UNNEST([
            IF(f.modelo_api_concorda, 'modelo da API concorda com o lado (+7)', NULL),
            IF(f.linha_sharp_confirma, 'linha da Pinnacle se moveu pro nosso lado (+8)', NULL)
        ]) AS x WHERE x IS NOT NULL)
    ) AS evidencias,

    -- avisos: penalidades específicas do mercado + penalidades globais de odds + cegueira.
    -- O aviso de cegueira NÃO leva pontos entre parênteses como os outros, e é de propósito
    -- (#41, ADR 0003): ele não desconta nada. Ele diz que a nota saiu de menos informação —
    -- incompleta, não contrária. Vem por último porque é o único que não é red flag do preço.
    ARRAY_CONCAT(
        p.avisos_especificos,
        ARRAY(SELECT y FROM UNNEST([
            IF(f.pen_odd_outlier,  '⚠ odd fora da média — provável linha mole/erro (−30)', NULL),
            IF(f.pen_poucas_casas, '⚠ poucas casas cobrindo o mercado (−12)', NULL),
            IF(f.pen_odd_longshot, '⚠ odd muito alta / longshot (−15)', NULL),
            IF(f.pen_odd_juice,    '⚠ retorno baixo / juice (−10)', NULL),
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

    -- componentes (transparência/debug)
    f.penalidades_globais_pts,
    -- AS PARCELAS DA SOMA ACIMA (#87), agora lidas do funil em vez de recompostas do de-vig.
    -- A identidade 30*outlier + 12*poucas + 15*longshot + 10*juice = penalidades_globais_pts
    -- vale em todo ramo (na DC o juice é FALSE de propósito) e segue medida por
    -- assert_penalidades_globais_decompostas.
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
-- matar — e, de quebra, arrastaria para o board as três barreiras de preço da #104, que
-- estão FORA da conjunção gravada de propósito, até a virada (#109).
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
        {{ futebol_expurga_do_board('fx._fx_status_short', 'fx._fx_kickoff_utc') }},
        FALSE
      )
