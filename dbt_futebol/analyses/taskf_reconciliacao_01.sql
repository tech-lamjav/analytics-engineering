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

    A régua está em `taskf_tolerancia_pp` (default 0,5 pp), aplicada só sobre a origem 1. O valor
    é declarado e justificado por escrito em `docs/TASKF_RESULTADOS.md` — aqui ele é só o número.

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

    Consequência: `DENTRO_DA_TOLERANCIA` aqui significa "passou na régua declarada", e NÃO
    "explicado". A régua foi declarada antes de medir, e continua valendo como bar; o que a
    medição acrescenta é que a única linha que a usou não tem a causa que a justificaria. O
    resíduo está documentado em `docs/TASKF_RESULTADOS.md`, aberto e delimitado.

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

{%- set tol = var('taskf_tolerancia_pp', 0.5) -%}

{#- As duas premissas que leem odds ao vivo. Não é uma lista de exceções conveniente: é o
    conjunto exato das que comparam preço com preço, e ele sai do catálogo do Motor. Qualquer
    outra premissa lê fixture, estatística ou tabela — tudo determinístico sobre o mesmo
    universo congelado. -#}
{%- set premissas_de_odds = ['linha_subindo', 'linha_descendo'] -%}

WITH {{ taskf_publicado_01() }},

medido AS (
    SELECT
        mercado, premissa, benchmark, usado_para_peso,
        jogos_no_universo, medido_em, git_sha,
        n_p0, a_odd_dava_p0, aconteceu_p0, diferenca_p0,
        jogos_medios, pct_amostra_curta, peso_p0, peso_p0_k0,
        n_p5, diferenca_p5, diferenca_p10
    FROM {{ source('futebol_taskF', 'taskf_teste2') }}
    WHERE celula = 'base'
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
    SELECT
        *,
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
        (IF(jogos_medios_pub IS NOT NULL AND jogos_medios_medido IS DISTINCT FROM jogos_medios_pub, 1, 0)
       + IF(pct_curta_pub    IS NOT NULL AND pct_curta_medido    IS DISTINCT FROM pct_curta_pub,    1, 0)
       + IF(peso_p0_pub      IS NOT NULL AND peso_p0_medido      IS DISTINCT FROM peso_p0_pub,      1, 0)
       + IF(peso_p0_k0_pub   IS NOT NULL AND peso_p0_k0_medido   IS DISTINCT FROM peso_p0_k0_pub,   1, 0)
       + IF(n_p0_pub         IS NOT NULL AND n_p0_medido         IS DISTINCT FROM n_p0_pub,         1, 0)
       + IF(n_p5_pub         IS NOT NULL AND n_p5_medido         IS DISTINCT FROM n_p5_pub,         1, 0)) AS campos_divergentes_nao_pp,

        CASE
            WHEN premissa IN ({{ premissas_de_odds | map('tojson') | join(', ') }})
                THEN 'deriva_de_odds'
            {#- O consenso é o benchmark preferido do BTTS, e é onde as 172 linhas degeneradas da
                spec #22 viviam. Toda linha de BTTS carrega essa origem por construção. -#}
            WHEN mercado = 'BTTS' THEN 'correcao_22'
            ELSE 'investigar'
        END AS origem
    FROM juntado
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
    campos_divergentes_nao_pp,
    ROUND(maior_delta_pp, 1) AS maior_delta_pp,
    {{ tol }} AS tolerancia_pp,
    CASE
        WHEN so_no_medido OR so_no_publicado    THEN 'SEM_CONTRAPARTE'
        WHEN campos_comparados = 0              THEN 'NADA_A_COMPARAR'
        WHEN maior_delta_pp = 0
             AND campos_divergentes_nao_pp = 0  THEN 'EXATO'
        WHEN origem = 'deriva_de_odds'
             AND maior_delta_pp <= {{ tol }}    THEN 'DENTRO_DA_TOLERANCIA'
        WHEN origem = 'deriva_de_odds'          THEN 'DERIVA_ACIMA_DA_TOLERANCIA'
        WHEN origem = 'correcao_22'             THEN 'EXPLICADA_PELA_CORRECAO_22'
        ELSE                                         'INVESTIGAR'
    END AS veredito,
    jogos_no_universo,
    medido_em,
    git_sha
FROM classificado
ORDER BY maior_delta_pp DESC, mercado, premissa
