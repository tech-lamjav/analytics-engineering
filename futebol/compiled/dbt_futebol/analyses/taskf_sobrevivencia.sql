/*
    [F-9] QUAIS PREMISSAS SOBREVIVEM QUANDO O HISTÓRICO É REAL — o veredito, por regra escrita.

    A spec #49 (user story 6) e o critério de aceite da #58 pedem uma resposta fechada sobre as
    QUATRO premissas de "muito sinal, pouca amostra" que abrem o problema: `clean_sheets_altos`,
    `superioridade_xg`, `tende_golear` e `defesa_forte`. Elas são as de maior peso aparente hoje e
    as de maior exposição a jogo sem histórico (77% a 88% das linhas com menos de 5 partidas
    disputadas). A pergunta é se o sinal delas sobrevive quando o histórico deixa de ser
    artificialmente curto — ou se ele era o artefato.

    As #53 e #54 já publicaram os números delas célula a célula. O que esta análise acrescenta, e
    é o que o critério de aceite pede, é o VEREDITO: uma regra escrita antes de olhar, aplicada
    mecanicamente, para "sobrevive" não ser leitura de tabela.

    ────────────────────────────────────────────────────────────────────────────────
    A REGRA, DECLARADA

    O QUE É "HISTÓRICO REAL". As células com o escopo solto — `escopo` e `ambos` —, porque a
    hipótese do ticket de origem é sobre ESCOPO: o histórico do time está contado dentro da
    competição do jogo, e por isso um time de Copa do Brasil com 2 jogos naquela competição é
    tratado como time sem passado. As outras duas células entram na saída como contexto: `base` é
    o que roda hoje e `recorte` isola o outro eixo.

    ONDE. No piso 5 — o piso da spec e o que a [0.1] usa como referência. Ver a ressalva de piso
    abaixo.

    O VEREDITO, por premissa:

      SOBREVIVE            `diferenca_p5` > 0 nas DUAS células de escopo solto (`escopo` e
                           `ambos`), e n_p5 >= 25 nas duas.
      SOBREVIVE_COM_RESSALVA   o sinal é positivo nas duas, mas em alguma delas n_p5 < 25.
      SEM_EVIDENCIA        qualquer outro caso — inclusive sinal positivo numa célula só.

    POR QUE AS DUAS, E NÃO UMA. Uma premissa que só melhora sob `ambos` melhora quando os DOIS
    eixos se soltam, e aí não dá para dizer se o que a salvou foi juntar competição ou parar de
    zerar na virada de temporada — que é exatamente a pergunta 9 da spec. Exigir as duas é exigir
    que o sinal não dependa de qual eixo se mexeu.

    POR QUE n >= 25. É o ponto em que o encolhimento `n/(n+50)` que o Teste 2 aplica ao peso passa
    de 1/3 — abaixo disso, dois terços de qualquer ganho medido são descartados por falta de
    amostra, e chamar isso de "sobreviveu" seria emprestar ao número uma confiança que a própria
    fórmula do peso recusa. O corte sai da constante k=50 que já existe, e não de uma régua nova.

    ⚠️ ISTO NÃO É RECOMENDAÇÃO DE PESO, e a distinção não é formalidade. A [0.1] mediu que ganho
    de premissa medido in-sample não se replica out-of-sample (+10,0% virou −6,2%), e a spec #49
    põe peso explicitamente fora de escopo. "Sobrevive" aqui quer dizer "a evidência que a [B] vai
    ler continua de pé quando o histórico é real", e não "vale apostar nela".

    ⚠️ E O VEREDITO É NO PISO 5 PORQUE A PERGUNTA É SOBRE AMOSTRA CURTA. No piso 0 as quatro
    continuam parecendo boas — é essa aparência que a [F] existe para desmontar. A saída traz os
    quatro pisos no detalhe para quem quiser ver a régua se mexer.

    ────────────────────────────────────────────────────────────────────────────────
    DOIS BLOCOS

      quatro     as quatro premissas que a spec nomeia, com o número em cada uma das quatro
                 células e o veredito.
      catalogo   a MESMA regra aplicada às 39, resumida. Existe para o veredito das quatro não ser
                 lido isolado: se metade do catálogo "sobrevive", sobreviver não significa nada.
                 É a conferência de que a régua discrimina.

    COMO RODAR (do dbt_futebol/), depois das quatro células medidas:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_sobrevivencia
      bq query --use_legacy_sql=false --project_id=smartbetting-dados --max_rows=500 \
        < target/compiled/dbt_futebol/analyses/taskf_sobrevivencia.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento; e sem
    `--max_rows` ele trunca em 100 linhas sem avisar.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/WITH medido AS (
    SELECT *
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE universo = 'completo'
      AND usado_para_peso
),


por_premissa AS (
    SELECT
        mercado,
        premissa,
        benchmark,
        MAX(IF(celula = 'base', diferenca_p5, NULL)) AS dif_base,
        MAX(IF(celula = 'base', n_p5,         NULL)) AS n_base,
        MAX(IF(celula = 'base', peso_p5,      NULL)) AS peso_base,
        MAX(IF(celula = 'base', pct_amostra_curta,              NULL)) AS curta_base,
        MAX(IF(celula = 'escopo', diferenca_p5, NULL)) AS dif_escopo,
        MAX(IF(celula = 'escopo', n_p5,         NULL)) AS n_escopo,
        MAX(IF(celula = 'escopo', peso_p5,      NULL)) AS peso_escopo,
        MAX(IF(celula = 'escopo', pct_amostra_curta,              NULL)) AS curta_escopo,
        MAX(IF(celula = 'recorte', diferenca_p5, NULL)) AS dif_recorte,
        MAX(IF(celula = 'recorte', n_p5,         NULL)) AS n_recorte,
        MAX(IF(celula = 'recorte', peso_p5,      NULL)) AS peso_recorte,
        MAX(IF(celula = 'recorte', pct_amostra_curta,              NULL)) AS curta_recorte,
        MAX(IF(celula = 'ambos', diferenca_p5, NULL)) AS dif_ambos,
        MAX(IF(celula = 'ambos', n_p5,         NULL)) AS n_ambos,
        MAX(IF(celula = 'ambos', peso_p5,      NULL)) AS peso_ambos,
        MAX(IF(celula = 'ambos', pct_amostra_curta,              NULL)) AS curta_ambos,
        MAX(IF(celula = 'escopo', diferenca_p0, NULL)) AS dif_escopo_p0,
        MAX(IF(celula = 'ambos',  diferenca_p0, NULL)) AS dif_ambos_p0,
        MAX(IF(celula = 'escopo', diferenca_p3, NULL)) AS dif_escopo_p3,
        MAX(IF(celula = 'ambos',  diferenca_p3, NULL)) AS dif_ambos_p3,
        MAX(IF(celula = 'escopo', diferenca_p5, NULL)) AS dif_escopo_p5,
        MAX(IF(celula = 'ambos',  diferenca_p5, NULL)) AS dif_ambos_p5,
        MAX(IF(celula = 'escopo', diferenca_p10, NULL)) AS dif_escopo_p10,
        MAX(IF(celula = 'ambos',  diferenca_p10, NULL)) AS dif_ambos_p10,
        COUNT(DISTINCT celula) AS celulas
    FROM medido
    GROUP BY mercado, premissa, benchmark
),


julgado AS (
    SELECT
        p.*,
        p.premissa IN ("clean_sheets_altos", "superioridade_xg", "tende_golear", "defesa_forte") AS uma_das_quatro,
        CASE
            WHEN p.dif_escopo IS NULL OR p.dif_ambos IS NULL
                THEN 'SEM_EVIDENCIA'
            WHEN p.dif_escopo > 0 AND p.dif_ambos > 0
                 AND p.n_escopo >= 25
                 AND p.n_ambos  >= 25
                THEN 'SOBREVIVE'
            WHEN p.dif_escopo > 0 AND p.dif_ambos > 0
                THEN 'SOBREVIVE_COM_RESSALVA'
            ELSE 'SEM_EVIDENCIA'
        END AS veredito
    FROM por_premissa AS p
)

SELECT 1 AS ordem, 'quatro' AS bloco,
    premissa AS chave,
    veredito,
    dif_escopo AS dif_escopo,
    dif_ambos  AS dif_ambos,
    CAST(n_escopo AS FLOAT64) AS n_escopo,
    TO_JSON_STRING(STRUCT(
        mercado, benchmark, celulas,
        dif_base    AS dif_base,    n_base    AS n_base,
        dif_recorte AS dif_recorte, n_recorte AS n_recorte,
        n_ambos AS n_ambos,
        peso_base AS peso_base, peso_escopo AS peso_escopo,
        peso_recorte AS peso_recorte, peso_ambos AS peso_ambos,
        curta_base AS curta_base, curta_escopo AS curta_escopo,
        curta_recorte AS curta_recorte, curta_ambos AS curta_ambos,
        dif_escopo_p0, dif_ambos_p0,
        dif_escopo_p3, dif_ambos_p3,
        dif_escopo_p5, dif_ambos_p5,
        dif_escopo_p10, dif_ambos_p10
    )) AS detalhe
FROM julgado
WHERE uma_das_quatro

UNION ALL

SELECT 2, 'catalogo',
    veredito,
    FORMAT('%d de %d premissas', COUNT(*), (SELECT COUNT(*) FROM julgado)),
    CAST(COUNT(*) AS FLOAT64),
    CAST(COUNTIF(uma_das_quatro) AS FLOAT64),
    ROUND(AVG(dif_escopo), 2),
    TO_JSON_STRING(STRUCT(
        STRING_AGG(premissa, ', ' ORDER BY premissa) AS quais,
        STRING_AGG(IF(uma_das_quatro, premissa, NULL), ', ' ORDER BY premissa) AS quais_das_quatro,
        5 AS piso_do_veredito, 25 AS n_minimo,
        'completo' AS universo
    ))
FROM julgado
GROUP BY veredito

ORDER BY ordem, chave