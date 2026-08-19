{#
    [F-2] RECONCILIAÇÃO: a célula `base` contra o Teste 2 publicado da Task [0.1].

    `base` é a célula que não muda nada — escopo na competição do jogo, recorte na temporada
    corrente, que é o que roda hoje. Se ela não reproduz o número publicado, o caminho inteiro da
    medição (var → target → dataset → Teste 2 → comparação) está errado em algum ponto, e as
    outras três células não têm como significar coisa alguma. É o tracer bullet: o caso em que a
    resposta já é conhecida.

    ────────────────────────────────────────────────────────────────────────────────
    A TOLERÂNCIA COBRE UMA ORIGEM DE DIVERGÊNCIA, E SÓ UMA

    A [0.1] rodou em 04/08 e esta medição roda depois. Entre as duas execuções o número de uma
    premissa pode andar por motivos diferentes, e tratá-los como um só é o que transformaria a
    tolerância em desculpa. São três, e a saída os separa em `origem`:

    1. `deriva_de_odds` — a ÚNICA que a tolerância cobre. `linha_subindo` e `linha_descendo` leem
       odds ao vivo: elas acendem comparando o preço de abertura com o de fechamento, e o
       fechamento é a última janela de coleta disponível NO MOMENTO DO BUILD. Uma janela t15m que
       chegou depois de 04/08 muda quais linhas acendem, então tanto a `diferença` quanto o `n`
       andam sozinhos, sem bug. Já medido no repositório: o mercado de Gols não é reproduzível
       entre builds, e a mesma query devolve −7,4 e −7,6 em dias diferentes.

    2. `correcao_22` — divergência de OUTRA origem, que a tolerância NÃO cobre e que a saída
       marca para ser explicada. A spec #22 corrigiu o de-vig em 05/08, DEPOIS da publicação: o
       conjunto de saídas incompleto deixou de emitir valor. Os números publicados incluíam 172
       linhas dessas no Teste 2 (2 vitórias em 172, ROI −35,5%) — TODAS de consenso. Elas não
       existem mais. Então a reprodução exata do que foi publicado no benchmark de consenso é
       impossível por construção, e o BTTS é o mercado atingido no lugar que dói, porque o
       benchmark preferido dele é justamente o consenso. Isto não é deriva; é uma correção
       conhecida, e o lugar dela é a coluna de origem e o doc de resultados, não a folga.

    3. `investigar` — o resto. Premissa que não lê odds, em mercado ancorado na Pinnacle, medida
       sobre o mesmo universo congelado: deveria ser DETERMINÍSTICA. Diferença aqui não tem
       explicação pronta e é achado até que se prove o contrário.

    A régua está em `taskf_tolerancia_pp` (default 0,25 pp), aplicada só sobre a origem 1. O valor
    é declarado e justificado por escrito em `docs/TASKF_RESULTADOS.md` — aqui ele é só o número.

    ⚠️ ERA 0,5 pp ATÉ 19/08/2026, e desceu na #92 porque o 0,5 nunca tinha sido medido: ele saiu
    de uma frase sobre deltas de ROI do TESTE 3 ("0,2–0,4 pp entre execuções"), enquanto esta
    régua governa campos do TESTE 2 — que, na reconciliação de 04/08, reproduziram com delta
    exatamente 0,0. A #78 tirou o ruído de instrumento que alimentava aqueles 0,2–0,4, e a #92
    remediu: 0,00 pp em 8 execuções, nas duas camadas (reconstrução das premissas e agregação do
    Teste 2). O que sobrou dentro do 0,25 é o resíduo conhecido do `linha_descendo` (0,2 pp
    medido) mais meia grade do `ROUND(·, 1)`, que tira o número de cima da grade. A decomposição
    inteira está no cabeçalho da tests/assert_taskf_base_reproduz_01.sql — a régua existe uma vez,
    o argumento também.

    ⚠️ O QUE A PRIMEIRA EXECUÇÃO MOSTROU, e que muda como esta saída deve ser lida (12/08/2026):

    - A origem 2 tem footprint ZERO nas 39 linhas publicadas, e isso foi medido, não suposto. Na
      janela congelada, 1X2, BTTS e Dupla Chance não têm NENHUMA linha de conjunto incompleto; as
      237 que existem estão em Handicap (58) e Gols (179) e são TODAS de consenso puro — nenhuma
      delas tem preço da Pinnacle em nenhuma janela, conferido contra um controle que casa 3.370
      de 6.566 linhas normais, então o join não é vácuo. Como o benchmark preferido de Handicap e
      Gols é o sharp, a correção não alcança nenhuma linha comparada. O `correcao_22` continua na
      classificação porque a próxima janela de medição pode não ter essa sorte.

    - A origem 1 NÃO TEM MECANISMO NESTA JANELA. A coleta de odds é forward-only e para no
      apito: para os 169 jogos congelados, ZERO capturas com data posterior a 04/08 em qualquer
      das três janelas de fechamento. O insumo de `linha_caiu` (média das probabilidades
      implícitas de todas as casas, t24h → t15m) é, portanto, imóvel. "As odds viram sozinhas
      entre builds" é verdade no board vivo e FALSA num universo congelado do passado — e essa
      distinção não estava escrita em lugar nenhum antes desta medição.

    Consequência: nesta janela NENHUMA linha se classifica como `deriva_de_odds`, porque o
    mecanismo não existe — `linha_descendo` cai em `INVESTIGAR`, que é o veredito honesto, e o
    resíduo está documentado em `docs/TASKF_RESULTADOS.md`, aberto e delimitado. A régua continua
    declarada e continua valendo — mas vale **0,25 pp desde a #92**, e não os 0,5 que esta seção
    dizia. A frase que estava aqui ("volta a ter mordida no universo estendido da spec") deixou de
    ser a justificativa do número: o estendido nunca foi medido, e o que sustenta o 0,25 é o
    resíduo do `linha_descendo` mais meia grade. O estendido segue sendo onde
    `capturas_apos_o_teto` deixa de ser zero — e por isso segue precisando de medição PRÓPRIA
    antes que alguém reuse este número lá.

    É por isso que os dois mecanismos são MEDIDOS e vão na saída (`capturas_apos_o_teto`,
    `linhas_da_22_no_preferido`): quem lê não precisa acreditar no rótulo, ele vem com o número
    que o produziu.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE É COMPARÁVEL, POR LINHA

    O doc publica três recortes diferentes (ver macros/taskf_publicado_01.sql), então nem toda
    linha tem todo campo. `campos_comparados` diz quantos de fato foram conferidos, e
    `sem_contraparte` marca a linha medida que não tem número publicado nenhum. Sem isso,
    "bateu" fica indistinguível de "não havia o que comparar" — que é o modo de falha silencioso
    de qualquer reconciliação.

    Só o benchmark PREFERIDO de cada mercado entra: é o recorte que o doc publica. As linhas de
    consenso do Handicap e do Gols (`usado_para_peso = false`) não têm contraparte e ficam de
    fora da comparação de propósito.

    Rodar com (depois de taskf_teste2 ter materializado a célula `base`):

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_reconciliacao_01
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_reconciliacao_01.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
#}

{%- set tol = var('taskf_tolerancia_pp', 0.25) -%}
{%- set j   = taskf_universo() -%}

{#- As duas premissas que leem odds ao vivo. Não é uma lista de exceções conveniente: é o
    conjunto exato das que comparam preço com preço, e ele sai do catálogo do Motor. Qualquer
    outra premissa lê fixture, estatística ou tabela — tudo determinístico sobre o mesmo
    universo congelado. -#}
{%- set premissas_de_odds = ['linha_subindo', 'linha_descendo'] -%}

WITH {{ taskf_publicado_01() }},

jogos_congelados AS (
    SELECT fixture_id
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND {{ taskf_universo_filtro() }}
),

{#- ─────────────────────────────────────────────────────────────────────────────────────
    OS DOIS MECANISMOS SÃO MEDIDOS, NÃO SUPOSTOS.

    A primeira versão desta análise rotulava a origem por dedução de mesa: "é premissa de odds,
    logo é deriva" e "é BTTS, logo é a #22". Rótulo deduzido vira desculpa automática — um BTTS
    que divergisse por qualquer motivo sairia carimbado como explicado, sem ninguém olhar, e a
    #55 consumiria esse veredito como predicado. Os dois viraram medição.
    ───────────────────────────────────────────────────────────────────────────────────── -#}

{#- MECANISMO 1 — a deriva de odds é possível NESTA janela? Só é se tiver chegado captura depois
    do teto do universo. A coleta é forward-only e para no apito, então para uma janela do passado
    isto é zero, e "as odds viraram sozinhas" deixa de ser explicação disponível. Numa janela que
    alcance o presente (o universo estendido da spec) deixa de ser zero, e aí o rótulo volta a
    valer sozinho. -#}
deriva AS (
    SELECT COUNTIF(o.collection_date > DATE('{{ j.teto_utc }}')) AS capturas_apos_o_teto
    FROM {{ ref('fact_odds_snapshot') }} AS o
    JOIN jogos_congelados USING (fixture_id)
),

{#- MECANISMO 2 — a correção da spec #22 alcança o benchmark PREFERIDO de qual mercado?

    Uma linha que o de-vig deixou de emitir só move um número comparado se ela estivesse no
    benchmark preferido daquele mercado. E isso depende do mercado:

      BTTS (8)                    preferido = consenso  -> QUALQUER linha nulada o alcança.
      1X2 (1), Handicap (4),      preferido = sharp     -> só alcança se a Pinnacle precificava
      Gols (5)                                             aquela linha; sem Pinnacle a linha
                                                           nulada era de consenso e o consenso
                                                           não pesa nesses mercados.
      Dupla Chance (12)           preferido = derivada do de-vig 1X2 da Pinnacle -> mesma regra. -#}
pinnacle_nas_linhas AS (
    SELECT DISTINCT
        fixture_id,
        market_id,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM {{ ref('fact_odds_snapshot') }}
    WHERE bookmaker_id = 4
),

nuladas_pela_22 AS (
    SELECT
        d.market_id,
        p.fixture_id IS NOT NULL AS tinha_pinnacle
    FROM {{ ref('int_futebol_odds_devig') }} AS d
    JOIN jogos_congelados USING (fixture_id)
    LEFT JOIN pinnacle_nas_linhas AS p
           ON  p.fixture_id = d.fixture_id
           AND p.market_id  = d.market_id
           AND p.line_key   = COALESCE(CAST(d.line_value AS STRING), 'NONE')
    WHERE d.market_id IN ({{ task01_markets().keys() | join(', ') }})
      AND COALESCE(d.n_outcomes_valor < 2, TRUE)
),

alcance_22 AS (
    SELECT
        CASE market_id
            {%- for mid, m in task01_markets().items() %}
            WHEN {{ mid }} THEN '{{ m.nome }}'
            {%- endfor %}
        END AS mercado,
        COUNT(*)                                        AS linhas_nuladas,
        IF(market_id = 8, COUNT(*), COUNTIF(tinha_pinnacle)) AS alcanca_o_preferido
    FROM nuladas_pela_22
    GROUP BY market_id
),

medido AS (
    SELECT
        mercado, premissa, benchmark, usado_para_peso,
        jogos_no_universo, medido_em, git_sha,
        n_p0, a_odd_dava_p0, aconteceu_p0, diferenca_p0,
        {#- A [0.1] publicou UM `jogos_medios`, e a #54 desdobrou a coluna em duas. Aqui vale a
            DISPONÍVEL, e a escolha não muda nada nesta comparação: a célula é a `base`, cujo
            recorte é `temporada`, e sem teto as duas contagens são o mesmo número por
            construção. Ver o cabeçalho de analyses/taskf_teste2.sql. -#}
        jogos_medios_disp AS jogos_medios, pct_amostra_curta, peso_p0, peso_p0_k0,
        n_p5, diferenca_p5, diferenca_p10
    FROM {{ source('futebol_taskF', 'taskf_teste2') }}
    WHERE celula = 'base'
      AND universo = 'completo'
      AND usado_para_peso
),

{#- FULL OUTER para que a linha publicada sem contraparte medida apareça — 39 de cada lado é o
    esperado, e um FULL OUTER é o que denuncia quando não é. -#}
juntado AS (
    SELECT
        COALESCE(m.mercado,  p.mercado)  AS mercado,
        COALESCE(m.premissa, p.premissa) AS premissa,
        m.jogos_no_universo,
        m.medido_em,
        m.git_sha,
        m.mercado  IS NULL AS so_no_publicado,
        p.mercado  IS NULL AS so_no_medido,

        m.n_p0              AS n_p0_medido,          p.n_p0              AS n_p0_pub,
        m.diferenca_p0      AS dif_p0_medido,        p.diferenca_p0      AS dif_p0_pub,
        m.a_odd_dava_p0     AS a_odd_dava_p0_medido, p.a_odd_dava_p0     AS a_odd_dava_p0_pub,
        m.aconteceu_p0      AS aconteceu_p0_medido,  p.aconteceu_p0      AS aconteceu_p0_pub,
        m.jogos_medios      AS jogos_medios_medido,  p.jogos_medios      AS jogos_medios_pub,
        m.pct_amostra_curta AS pct_curta_medido,     p.pct_amostra_curta AS pct_curta_pub,
        m.peso_p0           AS peso_p0_medido,       p.peso_p0           AS peso_p0_pub,
        m.peso_p0_k0        AS peso_p0_k0_medido,    p.peso_p0_k0        AS peso_p0_k0_pub,
        m.n_p5              AS n_p5_medido,          p.n_p5              AS n_p5_pub,
        m.diferenca_p5      AS dif_p5_medido,        p.diferenca_p5      AS dif_p5_pub,
        m.diferenca_p10     AS dif_p10_medido,       p.diferenca_p10     AS dif_p10_pub
    FROM medido AS m
    FULL OUTER JOIN publicado_01 AS p
      ON  p.mercado  = m.mercado
      AND p.premissa = m.premissa
),

classificado AS (
    {#- `jt.*` e não `*`: os dois CTEs de mecanismo entram por CROSS/LEFT JOIN e um `*` traria as
        colunas deles duas vezes (a projeção abaixo já as nomeia). -#}
    SELECT
        jt.*,
        {#- A maior divergência entre os pisos publicados é o que decide o veredito da linha: uma
            premissa que bate no piso 0 e erra 9 pp no piso 5 não "bateu". -#}
        GREATEST(
            COALESCE(ABS(dif_p0_medido  - dif_p0_pub),  0),
            COALESCE(ABS(dif_p5_medido  - dif_p5_pub),  0),
            COALESCE(ABS(dif_p10_medido - dif_p10_pub), 0)
        ) AS maior_delta_pp,

        (IF(dif_p0_pub        IS NOT NULL, 1, 0)
       + IF(dif_p5_pub        IS NOT NULL, 1, 0)
       + IF(dif_p10_pub       IS NOT NULL, 1, 0)
       + IF(n_p0_pub          IS NOT NULL, 1, 0)
       + IF(n_p5_pub          IS NOT NULL, 1, 0)
       + IF(a_odd_dava_p0_pub IS NOT NULL, 1, 0)
       + IF(aconteceu_p0_pub  IS NOT NULL, 1, 0)
       + IF(jogos_medios_pub  IS NOT NULL, 1, 0)
       + IF(pct_curta_pub     IS NOT NULL, 1, 0)
       + IF(peso_p0_pub       IS NOT NULL, 1, 0)
       + IF(peso_p0_k0_pub    IS NOT NULL, 1, 0)) AS campos_comparados,

        {#- Campos publicados que NÃO estão em pontos percentuais (contagem de jogos, fração,
            peso) não entram no `maior_delta_pp`, que é uma régua em pp. Entram aqui, como
            contagem de campos que bateram — divergência neles é achado do mesmo jeito, só não
            é comparável com a régua. -#}
        (IF(jogos_medios_pub  IS NOT NULL AND jogos_medios_medido  IS DISTINCT FROM jogos_medios_pub,  1, 0)
       + IF(pct_curta_pub     IS NOT NULL AND pct_curta_medido     IS DISTINCT FROM pct_curta_pub,     1, 0)
       + IF(peso_p0_pub       IS NOT NULL AND peso_p0_medido       IS DISTINCT FROM peso_p0_pub,       1, 0)
       + IF(peso_p0_k0_pub    IS NOT NULL AND peso_p0_k0_medido    IS DISTINCT FROM peso_p0_k0_pub,    1, 0)
       + IF(n_p0_pub          IS NOT NULL AND n_p0_medido          IS DISTINCT FROM n_p0_pub,          1, 0)
       + IF(n_p5_pub          IS NOT NULL AND n_p5_medido          IS DISTINCT FROM n_p5_pub,          1, 0)
       + IF(a_odd_dava_p0_pub IS NOT NULL AND a_odd_dava_p0_medido IS DISTINCT FROM a_odd_dava_p0_pub, 1, 0)
       + IF(aconteceu_p0_pub  IS NOT NULL AND aconteceu_p0_medido  IS DISTINCT FROM aconteceu_p0_pub,  1, 0))
                                                                        AS campos_divergentes_fora_da_regua,

        d.capturas_apos_o_teto,
        COALESCE(a.alcanca_o_preferido, 0) AS linhas_da_22_no_preferido,

        {#- A ordem importa: uma premissa de odds num mercado que a #22 alcança é classificada
            como deriva, que é a origem mais específica dela. -#}
        CASE
            WHEN premissa IN ({{ premissas_de_odds | map('tojson') | join(', ') }})
                 AND d.capturas_apos_o_teto > 0            THEN 'deriva_de_odds'
            WHEN COALESCE(a.alcanca_o_preferido, 0) > 0    THEN 'correcao_22'
            ELSE 'investigar'
        END AS origem
    FROM juntado AS jt
    CROSS JOIN deriva AS d
    LEFT JOIN alcance_22 AS a ON a.mercado = jt.mercado
)

SELECT
    mercado,
    premissa,
    origem,
    campos_comparados,
    so_no_medido,
    so_no_publicado,
    n_p0_pub,  n_p0_medido,  n_p0_medido  - n_p0_pub  AS delta_n_p0,
    dif_p0_pub,  dif_p0_medido,  ROUND(dif_p0_medido  - dif_p0_pub,  1) AS delta_p0,
    dif_p5_pub,  dif_p5_medido,  ROUND(dif_p5_medido  - dif_p5_pub,  1) AS delta_p5,
    dif_p10_pub, dif_p10_medido, ROUND(dif_p10_medido - dif_p10_pub, 1) AS delta_p10,
    n_p5_pub, n_p5_medido, n_p5_medido - n_p5_pub AS delta_n_p5,
    a_odd_dava_p0_pub, a_odd_dava_p0_medido,
    aconteceu_p0_pub,  aconteceu_p0_medido,
    jogos_medios_pub,  jogos_medios_medido,
    pct_curta_pub,     pct_curta_medido,
    peso_p0_pub,       peso_p0_medido,
    peso_p0_k0_pub,    peso_p0_k0_medido,
    campos_divergentes_fora_da_regua,
    capturas_apos_o_teto,
    linhas_da_22_no_preferido,
    ROUND(maior_delta_pp, 1) AS maior_delta_pp,
    {{ tol }} AS tolerancia_pp,
    {#- A régua é em pp e cobre a DIFERENÇA. `EXATO` exige também que os campos publicados fora
        dela (n, jogos médios, % amostra curta, prob justa, acerto, pesos) tenham batido — senão
        "exato" significaria "exato no que a régua olha", que não é o que a palavra diz.
        `DENTRO_DA_TOLERANCIA` NÃO promete isso: leia `campos_divergentes_fora_da_regua` ao lado.
        E `CORRECAO_22_ALCANCA` não é veredito de aprovação — é o aviso de que aquele mercado tem
        linha nulada no benchmark preferido e, portanto, que a comparação ali não é limpa. -#}
    CASE
        WHEN so_no_medido OR so_no_publicado    THEN 'SEM_CONTRAPARTE'
        WHEN campos_comparados = 0              THEN 'NADA_A_COMPARAR'
        WHEN maior_delta_pp = 0
             AND campos_divergentes_fora_da_regua = 0 THEN 'EXATO'
        WHEN origem = 'deriva_de_odds'
             AND maior_delta_pp <= {{ tol }}    THEN 'DENTRO_DA_TOLERANCIA'
        WHEN origem = 'deriva_de_odds'          THEN 'DERIVA_ACIMA_DA_TOLERANCIA'
        WHEN origem = 'correcao_22'             THEN 'CORRECAO_22_ALCANCA'
        ELSE                                         'INVESTIGAR'
    END AS veredito,
    jogos_no_universo,
    medido_em,
    git_sha
FROM classificado
ORDER BY maior_delta_pp DESC, mercado, premissa
