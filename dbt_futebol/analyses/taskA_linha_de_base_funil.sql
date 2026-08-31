/*
    [A-106] A LINHA DE BASE REMEDIDA — o *antes* de toda comparação da task [A], LIDO DO FUNIL.

    ⚠️ OS NÚMEROS NÃO MORAM AQUI. Eles estão em `docs/TASKA_RESULTADOS.md`, seção do #106, com
    o instante da rodada publicada. Este cabeçalho carrega DECISÕES e PREDICADOS — o que muda
    quando a lógica muda. Foi guardar número em cabeçalho que deixou a `taskA_linha_de_base.sql`
    acumular três invalidações sem ninguém notar.

    Substitui `taskA_linha_de_base.sql`, que reimplementava os cinco ramos à mão. Duas medições
    da mesma coisa em semanas diferentes só são comparáveis se saírem da MESMA tabela.

    Fonte única: `fact_value_funnel`. Nenhum ramo é reconstruído aqui, nenhum `WHERE` de porta é
    reescrito. As oito portas já são COLUNAS BOOLEANAS lá (ADR 0011) — esta análise só as ordena
    numa fila e conta.

    ────────────────────────────────────────────────────────────────────────────────
    A JANELA ESTÁ FIXADA: `janela_e_corrente = TRUE`.

    São QUATRO janelas por candidato (`daily` < `t24h` < `t1h` < `t15m`) desde 07/08. Contar as
    quatro conta a mesma candidata até quatro vezes. A escolhida é a CORRENTE porque é a redução
    que o board publica — e é a mesma que a cópia à mão usa, sem o que a reconciliação compararia
    populações diferentes. O fator real de inflação está medido no documento de resultados, e ele
    é bem menor que o teto de 4× no escopo vivo: jogo futuro quase só tem `daily`.

    ────────────────────────────────────────────────────────────────────────────────
    DOIS ESCOPOS, E O HISTÓRICO CONTÉM O VIVO — de propósito.

      a. vivo       o que `futebol_funil_e_gravavel()` ainda deixa escrever — o MESMO predicado
                    do congelamento do funil, e não uma quarta cópia dele. Toda linha de jogo por
                    acontecer é reescrita a cada ciclo de odds, então ela carrega o código
                    CORRENTE por construção, e nenhuma linha de kickoff futuro tem carimbo
                    anterior à #91. É a linha de base sem confundidor.
                    ⚠️ Ele é SUBCONJUNTO ESTRITO da população que a ADR 0009 deixa no board, e
                    não o mesmo conjunto: o expurgo corta por STATUS, com o relógio só como rede
                    de 24 h, e `PST`/`SUSP`/`INT` sobrevivem ao kickoff no passado de propósito
                    ("um corte por relógio a mataria", diz o macro). O critério do ticket
                    ("população já expurgada") está satisfeito — nada de expurgado entra — mas
                    por um predicado MAIS ESTRITO, e o preço está medido no documento de
                    resultados. A escolha se justifica pelo que define o escopo: linha ainda
                    gravável é linha reescrita a cada ciclo, logo linha com o código de hoje.
                    Fixture sem kickoff conhecido entra aqui (fail-open, ADR 0003): ele é
                    gravável para sempre, logo carrega o código corrente.
      b. historico  o funil inteiro (o vivo INCLUSO). Compra uma ordem de grandeza de fixtures ao
                    preço de linhas cuja nota nasceu sob código mais velho. Uma linha viva
                    aparece nas duas — são duas leituras da mesma tabela, não uma partição, e
                    somar as duas conta as vivas duas vezes.

    ⚠️ `nota_valida_no_escopo` é COLUNA e não ressalva em prosa. A #91 (`887a1f9`) tocou apenas
    `int_futebol_premissas_*` e `int_futebol_team_form_pit`: ela muda a `porta_nota` e mais nada.
    As outras SETE portas são bit a bit idênticas antes e depois dela, e para elas o histórico
    inteiro é ganho puro de N. Só o que depende da nota sai `FALSE` no histórico — e quem decide
    isso é o campo `depende_da_nota` de cada linha da fila, nunca o texto do rótulo: rótulo é
    display, e casar contra ele faz um rename corromper a validade em silêncio.

    ────────────────────────────────────────────────────────────────────────────────
    AS TRÊS DESCONTINUIDADES DA SÉRIE, declaradas antes da medição:

      1. #91 (`887a1f9`), em produção 25/08 16:31:32 UTC (primeira execução com
         `PROCEDENCIA_SHA=887a1f9`). A única que parte a série, e só na `porta_nota`.
      2. O conserto do `.25` (#101), em produção 21/08 19:05 UTC. O ticket manda declará-lo como
         descontinuidade — e ele é, contra os números PUBLICADOS na rodada anterior. DENTRO da
         série ele não existe: o backfill que criou o funil rodou 21/08 21:21 UTC, depois dele.
         A seção 5 mede isso a cada rodada, em vez de afirmá-lo aqui.
      3. `origem = 'backfill'` — o build de 21/08 21:21 que criou a tabela, recalculado com o
         código daquele dia sobre odds antigas. A ADR 0011 o chama de "a única parte do funil que
         NÃO é registro de época". A seção 5 publica a fatia; `origem` está na tabela para quem
         quiser cortar.

    ────────────────────────────────────────────────────────────────────────────────
    O CONGELAMENTO DISPENSA SEED. A [F] congelou baseline num seed porque as tabelas eram
    rematerializadas; aqui o append-only (ADR 0011) É o congelamento. A fatia que esta análise
    lê fica preservada para sempre, e quem quiser reproduzir uma rodada exata — ou relê-la na
    véspera da A1, com N maior — acrescenta o predicado de corte:

        AND gravado_em <  TIMESTAMP '<instante da rodada>'   -- teto
        AND gravado_em >= TIMESTAMP '2026-08-25 16:31:32'    -- pós-#91, se quiser a nota limpa

    A entrega congela o PREDICADO, não uma cópia dos números. O `docs/TASKA_RESULTADOS.md` grava
    o instante de cada rodada publicada, e é ele que torna a rodada reproduzível.

    ────────────────────────────────────────────────────────────────────────────────
    A ORDEM DA FILA — e ela NÃO é a do `motivo_primario`.

        01 saída catalogada → 02 cobertura da Pinnacle → 03 valor estimável (ADR 0002)
        → 04 linha meia → 05 liquidez → 06 odd mínima da DC → 07 edge → 08 nota

    O `motivo_primario` do mart põe `linha_meia` e `odd_dc` no FIM da lista; aqui elas entram no
    meio, onde o ticket as põe. A divergência é deliberada e não muda nada em produção: o
    `motivo_primario` é conveniência de leitura de UMA linha (ADR 0011), e a leitura marginal sai
    dos booleanos, nunca dele. Quem lê marginal a partir de um campo de motivo único mede a ordem
    do `CASE`, não a severidade da porta.

    O ticket enumera seis portas e omite `porta_valor_estimavel` e `porta_odd_dc`. As duas estão
    aqui — é a mesma enumeração incompleta que a spec da [F] teve com AH e DC (#52), e uma fila
    com porta faltando devolve marginal errada em todas as seguintes.

    ⚠️ O ÚLTIMO DEGRAU DA FILA É `passou_no_gate`, LIDO DO MART — não a conjunção reescrita aqui.
    O mart deriva `passou_no_gate` das oito colunas e o seu cabeçalho diz que ela é "jamais
    escrita à mão"; uma nona cópia num arquivo de análise é como a expressão de meia-linha chegou
    a quatro cópias (#101/#114). Os prefixos `c1..c7` existem porque são o produto da análise — a
    conjunção inteira já existe e se lê.

    ⚠️ RESOLVIDO NA #118 (31/08): a porta que perguntava "a Pinnacle cobriu?" chamava-se
    `porta_conjunto_completo` e o nome escondia dois predicados diferentes por trás de um só.
    Ela virou `porta_cobertura_pinnacle` no mart — `pin_n_outcomes >= N`, exatamente a versão
    anterior à #22. A regra da ADR 0002 (`n_outcomes_valor = conjunto_esperado`) mora no de-vig
    e aparece aqui como `porta_valor_estimavel`; as duas nunca foram aninhadas. Este bloco só lê
    o mart — nada em produção muda nesta entrega.

    ⚠️ O EMPATE DO 1X2 SAI DA FILA (seção 2, com os números inteiros). Ele é um terço do universo
    do 1X2 POR CONSTRUÇÃO — nunca teve lado apostado, nenhuma premissa se aplica (ADR 0005/0006).
    Pôr uma população estruturalmente sem candidatura dentro de uma fila que mede severidade de
    porta infla o denominador de toda porta a montante e some no numerador da que interessa: a
    maioria dos empates reprova no EDGE, que vem ANTES da nota, então sob o motivo genérico
    (`sem_lado_apostado`) eles seriam contados por um fator de 3 a menos. O corte é a primeira
    linha do funil do 1X2 (a linha `00`, "com lado apostado") e a seção 2 publica os empates
    inteiros ao lado.

    ────────────────────────────────────────────────────────────────────────────────
    AS CINCO SEÇÕES (coluna `secao`), e o que `n_entrada`/`n_saida` querem dizer em cada uma.
    Em todas, `n_entrada` é o DENOMINADOR da linha e `n_saida` o numerador. `corte` é o eixo de
    cruzamento e só a seção 4 o usa; `n_isolado`/`n_marginal` só a seção 1.

      1. fila            a fila cumulativa. `n_isolado` = quantas ESTA porta remove sozinha do
                         universo (as somas se sobrepõem, uma linha reprova em várias);
                         `n_marginal` = quantas ela ainda remove DEPOIS das anteriores (as somas
                         fecham). É a marginal que diz o que a porta acrescenta.
      2. empate 1X2      os empates inteiros e onde eles caem. Fora da fila.
      3. nota            decis da nota, com as três faixas de hoje por cima. Decil porque no
                         funil a Baixa é a maioria e três baldes só dizem "quase tudo é Baixa";
                         e porque a A4 (#107) tem mandato para mover as fronteiras — o decil
                         sobrevive à mudança de escala, as faixas de hoje saem junto para a
                         comparação com o board continuar possível.
      4. barreiras A5    as barreiras PROPOSTAS pela A5 (#104), que NÃO estão em produção: faixa
                         de odd, `n_casas >= 4` e `pen_odd_outlier`. Ficam FORA da fila e fora do
                         cumulativo — uma porta que não existe não pode remover linha do *antes*,
                         ou o antes/depois da A5 mede zero contra zero. Saem por TRÊS eixos, e é
                         de propósito: `pts_premissas` (o eixo em que o ticket mediu), a NOTA
                         publicada (em que a direção se inverte) e `pts_premissas` restrito às
                         linhas com preço da Pinnacle (o recorte exato da frase do ticket).
      5. procedencia     `origem`, carimbo pré/pós-#91 e o efeito da janela. A auditoria da
                         própria medição, remedida a cada rodada em vez de afirmada em prosa.

    ────────────────────────────────────────────────────────────────────────────────
    ESTA ANÁLISE NÃO MUDA NADA EM PRODUÇÃO. `dbt compile` + `bq query`, e nada de `dbt run`.

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_linha_de_base_funil
      bq query --use_legacy_sql=false --format=csv \
        < target/compiled/dbt_futebol/analyses/taskA_linha_de_base_funil.sql
*/

{%- set FAIXA = "CASE WHEN {c} IS NULL THEN 'n. sem avaliacao'
                        WHEN {c} = 0     THEN '0. zero'
                        WHEN {c} < 30    THEN '1. 1-29'
                        ELSE                  '2. >=30' END" -%}

WITH funil AS (
    SELECT
        f.*,
        {# O histórico contém o vivo: duas leituras da mesma tabela, não uma partição. #}
        escopo
    FROM {{ ref('fact_value_funnel') }} f
    CROSS JOIN UNNEST(
        IF({{ futebol_funil_e_gravavel('f.kickoff_utc') }},
           ['a. vivo', 'b. historico'],
           ['b. historico'])
    ) AS escopo
    {# A JANELA FIXADA. Sem isto todo número abaixo infla. #}
    WHERE f.janela_e_corrente
),

{# ─────────────────────────────────────────────────────────────────────────────────
    AS OITO PORTAS, renomeadas UMA vez. O empate continua aqui dentro, marcado pela
    coluna que o mart já carrega — quem separa as duas populações é o `WHERE` de cada
    seção, e não uma segunda cópia deste bloco.
    ───────────────────────────────────────────────────────────────────────────────── #}
portas AS (
    SELECT
        escopo,
        market,
        score,
        pts_premissas,
        valor_fonte,
        best_odd,
        n_casas,
        pen_odd_outlier,
        origem,
        gravado_em,
        sem_lado_apostado,
        porta_saida_catalogada   AS p1,
        porta_cobertura_pinnacle AS p2,
        porta_valor_estimavel    AS p3,
        porta_linha_meia         AS p4,
        porta_liquidez           AS p5,
        porta_odd_dc             AS p6,
        porta_edge               AS p7,
        porta_nota               AS p8,
        {# a conjunção das oito, DERIVADA NO MART. Ver o ⚠️ do cabeçalho. #}
        passou_no_gate           AS c8
    FROM funil
),

{# `c_k` = passou em TODAS as portas até a k. A porta k remove `c_{k-1} AND NOT p_k`.
    `c8` não aparece aqui: ele é `passou_no_gate` e já veio pronto. #}
cum AS (
    SELECT
        *,
        p1                                                   AS c1,
        p1 AND p2                                            AS c2,
        p1 AND p2 AND p3                                     AS c3,
        p1 AND p2 AND p3 AND p4                              AS c4,
        p1 AND p2 AND p3 AND p4 AND p5                       AS c5,
        p1 AND p2 AND p3 AND p4 AND p5 AND p6                AS c6,
        p1 AND p2 AND p3 AND p4 AND p5 AND p6 AND p7         AS c7
    FROM portas
),

{# ─────────────────────────────────────────────────────────────────────────────────
    SEÇÃO 1 — A FILA. Sobre `NOT sem_lado_apostado`: o empate tem seção própria, e o
    corte é a linha `00`.
    ───────────────────────────────────────────────────────────────────────────────── #}
fila_long AS (
    SELECT escopo, market, f.*
    FROM cum
    CROSS JOIN UNNEST([
        {# `depende_da_nota` decide `nota_valida_no_escopo`. É um campo, e não um teste
            contra o rótulo: rótulo é display, e um rename não pode corromper a validade. #}
        STRUCT('00. universo (com lado apostado)' AS item, TRUE AS entrou, TRUE AS passou, TRUE AS passa_sozinha, FALSE AS depende_da_nota),
        STRUCT('01. saida catalogada',                     TRUE,           c1,             p1,                   FALSE),
        STRUCT('02. cobertura da Pinnacle (pin_n_outcomes)', c1,           c2,             p2,                   FALSE),
        STRUCT('03. valor estimavel (ADR 0002)',            c2,            c3,             p3,                   FALSE),
        STRUCT('04. linha meia (AH/Gols)',                  c3,            c4,             p4,                   FALSE),
        STRUCT('05. liquidez >= 3 casas',                   c4,            c5,             p5,                   FALSE),
        STRUCT('06. odd minima da DC (>= 1,25)',            c5,            c6,             p6,                   FALSE),
        STRUCT('07. edge acima do piso',                    c6,            c7,             p7,                   FALSE),
        STRUCT('08. nota >= 40',                            c7,            c8,             p8,                   TRUE)
    ]) AS f
    WHERE NOT sem_lado_apostado
),

sec_fila AS (
    SELECT
        escopo,
        '1. fila'                                      AS secao,
        item,
        mercado,
        CAST(NULL AS STRING)                           AS corte,
        COUNTIF(entrou)                                AS n_entrada,
        COUNTIF(NOT passa_sozinha)                     AS n_isolado,
        COUNTIF(entrou AND NOT passou)                 AS n_marginal,
        COUNTIF(entrou AND passou)                     AS n_saida,
        {# Só a porta de nota depende da #91; as outras sete são idênticas antes e depois. #}
        (escopo = 'a. vivo' OR NOT depende_da_nota)    AS nota_valida_no_escopo
    FROM fila_long, UNNEST([market, 'ZZ. TODOS']) AS mercado
    GROUP BY escopo, item, mercado, depende_da_nota
),

{# ─────────────────────────────────────────────────────────────────────────────────
    SEÇÃO 2 — O EMPATE DO 1X2, inteiro, e onde ele cai. Fora da fila, mesmos prefixos.
    ───────────────────────────────────────────────────────────────────────────────── #}
sec_empate AS (
    SELECT
        escopo,
        '2. empate 1X2'      AS secao,
        item,
        'match_winner'       AS mercado,
        CAST(NULL AS STRING) AS corte,
        COUNT(*)             AS n_entrada,
        CAST(NULL AS INT64)  AS n_isolado,
        CAST(NULL AS INT64)  AS n_marginal,
        COUNTIF(e)           AS n_saida,
        (escopo = 'a. vivo' OR NOT depende_da_nota) AS nota_valida_no_escopo
    FROM cum
    CROSS JOIN UNNEST([
        STRUCT('10. empates (universo)'              AS item, TRUE           AS e, FALSE AS depende_da_nota),
        STRUCT('11. reprova antes do edge',                   NOT c6,              FALSE),
        STRUCT('12. reprova NO edge',                         c6 AND NOT p7,       FALSE),
        STRUCT('13. chega a nota e reprova na nota',          c7 AND NOT p8,       TRUE),
        STRUCT('14. passaria em tudo (nota)',                 c8,                  TRUE)
    ])
    WHERE sem_lado_apostado
    GROUP BY escopo, item, depende_da_nota
),

{# ─────────────────────────────────────────────────────────────────────────────────
    SEÇÃO 3 — A NOTA POR FAIXA: decis, com as três faixas de hoje na mesma etiqueta.
    Denominador = quem CHEGA à porta de nota, que é o `c7` da fila e não uma terceira
    cópia da conjunção das sete.
    ───────────────────────────────────────────────────────────────────────────────── #}
sec_nota AS (
    SELECT
        escopo,
        '3. nota' AS secao,
        item,
        mercado,
        CAST(NULL AS STRING) AS corte,
        {# o denominador é o mesmo em todas as linhas do (escopo, mercado): quem CHEGOU à
            porta de nota. `SUM(COUNT(*)) OVER` e não `COUNT(*) OVER` — a janela roda DEPOIS
            do GROUP BY, e um COUNT ali contaria decis, não linhas. #}
        SUM(COUNT(*)) OVER (PARTITION BY escopo, mercado) AS n_entrada,
        CAST(NULL AS INT64) AS n_isolado,
        CAST(NULL AS INT64) AS n_marginal,
        COUNT(*)            AS n_saida,
        (escopo = 'a. vivo') AS nota_valida_no_escopo
    FROM (
        SELECT
            escopo,
            market,
            {# o decil, e a faixa de HOJE ao lado dele na mesma etiqueta: a A4 (#107) tem
                mandato para mover as fronteiras, e o decil sobrevive à mudança de escala. #}
            CONCAT(
                'D', CAST(LEAST(DIV(CAST(score AS INT64), 10), 9) AS STRING), ' (',
                CASE WHEN score >= 80 THEN 'ALTA'
                     WHEN score >= 60 THEN 'MEDIA'
                     WHEN score >= 40 THEN 'BAIXA'
                     ELSE 'fora da regua' END, ')'
            ) AS item
        FROM cum
        WHERE NOT sem_lado_apostado AND c7
    ), UNNEST([market, 'ZZ. TODOS']) AS mercado
    GROUP BY escopo, mercado, item
),

{# ─────────────────────────────────────────────────────────────────────────────────
    SEÇÃO 4 — AS BARREIRAS PROPOSTAS PELA A5 (#104), FORA DA FILA E FORA DO CUMULATIVO.
    Nenhuma está em produção. Cada uma sozinha, por três eixos — e são três porque as
    duas primeiras não concordam nem no SINAL, e a terceira é o recorte exato em que a
    frase do ticket foi medida.
    ───────────────────────────────────────────────────────────────────────────────── #}
barreiras AS (
    SELECT
        escopo,
        market,
        eixo || ' ' || faixa AS corte,
        b.item,
        b.passa
    FROM (
        SELECT
            escopo, best_odd, n_casas, pen_odd_outlier, market,
            e.eixo, e.faixa
        FROM cum
        CROSS JOIN UNNEST([
            STRUCT('1. pts_premissas' AS eixo,
                   {{ FAIXA.replace('{c}', 'pts_premissas') }} AS faixa),
            STRUCT('2. nota publicada',
                   {{ FAIXA.replace('{c}', 'score') }}),
            {# o recorte da frase do ticket: "entre linhas com preço da Pinnacle". Linha de
                consenso vira NULL e some no WHERE abaixo — o eixo mede o subconjunto, e não
                o universo com um rótulo enganoso por cima. #}
            STRUCT('3. pts_premissas (so Pinnacle)',
                   IF(valor_fonte <> 'pinnacle', NULL,
                      {{ FAIXA.replace('{c}', 'pts_premissas') }}))
        ]) AS e
        WHERE NOT sem_lado_apostado
          AND e.faixa IS NOT NULL
    )
    CROSS JOIN UNNEST([
        STRUCT('20. faixa de odd do mercado' AS item,
               best_odd BETWEEN IF(market = '{{ futebol_mercados_pontuados()[12] }}', 1.25, 1.50)
                            AND IF(market = '{{ futebol_mercados_pontuados()[12] }}', 2.00, 4.00) AS passa),
        STRUCT('21. liquidez >= 4 casas', n_casas >= 4),
        STRUCT('22. sem odd fora da curva', NOT pen_odd_outlier)
    ]) AS b
),

sec_barreiras AS (
    SELECT
        escopo,
        '4. barreiras A5 (nao estao em producao)' AS secao,
        item,
        mercado,
        corte,
        COUNT(*)            AS n_entrada,
        CAST(NULL AS INT64) AS n_isolado,
        CAST(NULL AS INT64) AS n_marginal,
        COUNTIF(passa)      AS n_saida,
        {# os três eixos leem a nota ou os pontos de premissa, e os dois vêm da #91. #}
        (escopo = 'a. vivo') AS nota_valida_no_escopo
    FROM barreiras, UNNEST([market, 'ZZ. TODOS']) AS mercado
    GROUP BY escopo, item, mercado, corte
),

{# ─────────────────────────────────────────────────────────────────────────────────
    SEÇÃO 5 — A PROCEDÊNCIA. A auditoria da própria medição: de onde vieram as linhas
    que os números acima contam. As duas descontinuidades de instante são MEDIDAS aqui
    a cada rodada, em vez de afirmadas no cabeçalho.
    ───────────────────────────────────────────────────────────────────────────────── #}
sec_procedencia AS (
    SELECT
        escopo,
        '5. procedencia'     AS secao,
        item,
        'ZZ. TODOS'          AS mercado,
        CAST(NULL AS STRING) AS corte,
        COUNT(*)             AS n_entrada,
        CAST(NULL AS INT64)  AS n_isolado,
        CAST(NULL AS INT64)  AS n_marginal,
        COUNTIF(e)           AS n_saida,
        TRUE                 AS nota_valida_no_escopo
    FROM cum
    CROSS JOIN UNNEST([
        STRUCT('30. linhas na janela corrente'    AS item, TRUE AS e),
        STRUCT('31. origem = backfill',           origem = 'backfill'),
        STRUCT('32. gravadas pos-#91',            gravado_em >= TIMESTAMP '2026-08-25 16:31:32'),
        STRUCT('33. gravadas pre-.25 (#101)',     gravado_em <  TIMESTAMP '2026-08-21 19:05:00'),
        STRUCT('34. publicadas (passou_no_gate)', c8)
    ])
    GROUP BY escopo, item
),

tudo AS (
    SELECT * FROM sec_fila
    UNION ALL SELECT * FROM sec_empate
    UNION ALL SELECT * FROM sec_nota
    UNION ALL SELECT * FROM sec_barreiras
    UNION ALL SELECT * FROM sec_procedencia
)

SELECT
    escopo,
    secao,
    item,
    mercado,
    corte,
    n_entrada,
    n_isolado,
    n_marginal,
    n_saida,
    ROUND(SAFE_DIVIDE(n_marginal, NULLIF(n_entrada, 0)) * 100, 1) AS pct_marginal,
    ROUND(SAFE_DIVIDE(n_saida,    NULLIF(n_entrada, 0)) * 100, 1) AS pct_saida,
    nota_valida_no_escopo,
    {# o instante da rodada, que é o que o predicado de corte congela. #}
    CURRENT_TIMESTAMP() AS medido_em
FROM tudo
ORDER BY escopo, secao, item, mercado, corte
