/*
    [F-6] A RE-MEDIÇÃO REPRODUZ A ANTERIOR? — as quatro células de hoje contra as quatro da
    execução passada, campo a campo.

    Por que existe. Mudar o schema da tabela acumulativa obriga a dropá-la e re-medir as quatro
    células (ver o cabeçalho de analyses/taskf_teste2.sql, FASE 0). Isso já aconteceu três vezes —
    na #54, na #55 e na #58 — e vai acontecer de novo. Toda vez, a mesma pergunta: a re-medição devolveu
    os mesmos números, ou alguma coisa andou junto?

    A #54 respondeu essa pergunta com uma cópia tratada como RASCUNHO — copiou as células da #53
    para uma tabela temporária, comparou, apagou a cópia. O resultado (119 de 120 linhas exatas)
    ficou verdadeiro e não re-derivável: quem quiser conferir hoje não tem contra o quê. O próprio
    doc de resultados registra a lição, e esta análise é ela cumprida: a cópia vira tabela
    declarada em `sources.yml` e a comparação vira arquivo.

    ⚠️ O QUE ESTA ANÁLISE **NÃO** É. Ela não confere que a medição está certa — para isso existem
    a reconciliação contra a [0.1] (analyses/taskf_reconciliacao_01.sql) e as três guardas da
    Costura B. Ela confere que a medição é ESTÁVEL: que reconstruir os seis modelos e rodar de
    novo, sobre os mesmos fatos, devolve o mesmo número. Duas execuções idênticas e ambas erradas
    passariam aqui.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE É COMPARADO, E O QUE NÃO É

    Todos os campos de MEDIÇÃO, nos quatro pisos, mais os do universo. Ficam de fora, e só eles:

      celula, mercado, premissa, benchmark   são a CHAVE da comparação.
      pit_escopo, pit_recorte                são função da célula.
      medido_em, git_sha                     mudam por definição entre duas execuções.
      odds_loaded_at                         não existe do lado antigo quando a re-medição foi
                                             causada justamente pela criação dessa coluna. Ele é
                                             cobrado pela primeira invariante da Costura B, que é
                                             onde a pergunta dele mora.
      universo                               idem, desde a #58: o lado de hoje é recortado no
                                             `completo` e comparado contra a cópia inteira, que só
                                             tinha esse universo. Ver abaixo.

    ⚠️ A COMPARAÇÃO É SÓ DO UNIVERSO `completo`, E É A ÚNICA COMPARAÇÃO QUE EXISTE (#58). Os três
    universos novos não têm lado esquerdo: eles nasceram nesta execução, e re-medição é uma
    pergunta sobre repetir. Comparar 240 linhas de hoje contra 60 de ontem produziria 180
    `SEM_CONTRAPARTE` que não significam nada — ruído que esconderia a divergência real, que é o
    único motivo de esta análise existir. Na próxima mudança de schema, a cópia já terá os quatro
    universos e este recorte deve cair junto com a var que o sustenta.

    A comparação passa por TO_JSON_STRING campo a campo: DATE, BOOL, INT64 e FLOAT64 convivem no
    mesmo formato longo, e NULL vira o texto `null` em vez de sumir da comparação — que é o modo
    de falha de quem compara com `=`.

    ⚠️ EMPATE DE ARREDONDAMENTO É A DIVERGÊNCIA ESPERADA, e não sinal de defeito. O `AVG` do
    BigQuery acumula em ponto flutuante e a ordem depende do layout físico da tabela, que muda
    quando os modelos são reconstruídos. Um valor exatamente em cima do meio da grade de
    `ROUND(·, 1)` — como uma fração de 51/400 = 12,75% — cai para 12,7 numa execução e 12,8 na
    seguinte. A #53 mediu três casos assim e a #54 mediu um. Quem ler um número divergente aqui
    deve primeiro conferir se ele é múltiplo da grade do `n` daquela linha; só depois procurar bug.

    COMO RODAR (do dbt_futebol/), depois das quatro células:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_remedicao \
        --vars '{taskf_remedicao_anterior: taskf_teste2_55}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_remedicao.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/WITH agora AS (
    SELECT * FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE universo = 'completo'
),antes AS (
    SELECT * FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2_55`
),juntado AS (
    SELECT
        COALESCE(a.celula, b.celula)       AS celula,
        COALESCE(a.mercado, b.mercado)     AS mercado,
        COALESCE(a.premissa, b.premissa)   AS premissa,
        COALESCE(a.benchmark, b.benchmark) AS benchmark,
        a.celula IS NULL AS so_no_anterior,
        b.celula IS NULL AS so_no_atual,
        a, b
    FROM agora AS a
    FULL OUTER JOIN antes AS b
      ON  b.celula    = a.celula
      AND b.mercado   = a.mercado
      AND b.premissa  = a.premissa
      AND b.benchmark = a.benchmark
),

por_campo AS (
    SELECT
        j.celula, j.mercado, j.premissa, j.benchmark,
        c.campo, c.agora, c.antes
    FROM juntado AS j,
    UNNEST([
        STRUCT('janela_ini'               AS campo,
               TO_JSON_STRING(j.a.janela_ini) AS agora,
               TO_JSON_STRING(j.b.janela_ini) AS antes),
        STRUCT('janela_fim'               AS campo,
               TO_JSON_STRING(j.a.janela_fim) AS agora,
               TO_JSON_STRING(j.b.janela_fim) AS antes),
        STRUCT('jogos_no_universo'               AS campo,
               TO_JSON_STRING(j.a.jogos_no_universo) AS agora,
               TO_JSON_STRING(j.b.jogos_no_universo) AS antes),
        STRUCT('linhas_no_universo'               AS campo,
               TO_JSON_STRING(j.a.linhas_no_universo) AS agora,
               TO_JSON_STRING(j.b.linhas_no_universo) AS antes),
        STRUCT('usado_para_peso'               AS campo,
               TO_JSON_STRING(j.a.usado_para_peso) AS agora,
               TO_JSON_STRING(j.b.usado_para_peso) AS antes),
        STRUCT('fator_encolhimento'               AS campo,
               TO_JSON_STRING(j.a.fator_encolhimento) AS agora,
               TO_JSON_STRING(j.b.fator_encolhimento) AS antes),
        STRUCT('jogos_medios_disp'               AS campo,
               TO_JSON_STRING(j.a.jogos_medios_disp) AS agora,
               TO_JSON_STRING(j.b.jogos_medios_disp) AS antes),
        STRUCT('jogos_medios_usado'               AS campo,
               TO_JSON_STRING(j.a.jogos_medios_usado) AS agora,
               TO_JSON_STRING(j.b.jogos_medios_usado) AS antes),
        STRUCT('pct_amostra_curta'               AS campo,
               TO_JSON_STRING(j.a.pct_amostra_curta) AS agora,
               TO_JSON_STRING(j.b.pct_amostra_curta) AS antes),
        STRUCT('peso_p0_k0'               AS campo,
               TO_JSON_STRING(j.a.peso_p0_k0) AS agora,
               TO_JSON_STRING(j.b.peso_p0_k0) AS antes),
        STRUCT('n_p0'               AS campo,
               TO_JSON_STRING(j.a.n_p0) AS agora,
               TO_JSON_STRING(j.b.n_p0) AS antes),
        STRUCT('a_odd_dava_p0'               AS campo,
               TO_JSON_STRING(j.a.a_odd_dava_p0) AS agora,
               TO_JSON_STRING(j.b.a_odd_dava_p0) AS antes),
        STRUCT('aconteceu_p0'               AS campo,
               TO_JSON_STRING(j.a.aconteceu_p0) AS agora,
               TO_JSON_STRING(j.b.aconteceu_p0) AS antes),
        STRUCT('diferenca_p0'               AS campo,
               TO_JSON_STRING(j.a.diferenca_p0) AS agora,
               TO_JSON_STRING(j.b.diferenca_p0) AS antes),
        STRUCT('peso_p0'               AS campo,
               TO_JSON_STRING(j.a.peso_p0) AS agora,
               TO_JSON_STRING(j.b.peso_p0) AS antes),
        STRUCT('n_p3'               AS campo,
               TO_JSON_STRING(j.a.n_p3) AS agora,
               TO_JSON_STRING(j.b.n_p3) AS antes),
        STRUCT('a_odd_dava_p3'               AS campo,
               TO_JSON_STRING(j.a.a_odd_dava_p3) AS agora,
               TO_JSON_STRING(j.b.a_odd_dava_p3) AS antes),
        STRUCT('aconteceu_p3'               AS campo,
               TO_JSON_STRING(j.a.aconteceu_p3) AS agora,
               TO_JSON_STRING(j.b.aconteceu_p3) AS antes),
        STRUCT('diferenca_p3'               AS campo,
               TO_JSON_STRING(j.a.diferenca_p3) AS agora,
               TO_JSON_STRING(j.b.diferenca_p3) AS antes),
        STRUCT('peso_p3'               AS campo,
               TO_JSON_STRING(j.a.peso_p3) AS agora,
               TO_JSON_STRING(j.b.peso_p3) AS antes),
        STRUCT('n_p5'               AS campo,
               TO_JSON_STRING(j.a.n_p5) AS agora,
               TO_JSON_STRING(j.b.n_p5) AS antes),
        STRUCT('a_odd_dava_p5'               AS campo,
               TO_JSON_STRING(j.a.a_odd_dava_p5) AS agora,
               TO_JSON_STRING(j.b.a_odd_dava_p5) AS antes),
        STRUCT('aconteceu_p5'               AS campo,
               TO_JSON_STRING(j.a.aconteceu_p5) AS agora,
               TO_JSON_STRING(j.b.aconteceu_p5) AS antes),
        STRUCT('diferenca_p5'               AS campo,
               TO_JSON_STRING(j.a.diferenca_p5) AS agora,
               TO_JSON_STRING(j.b.diferenca_p5) AS antes),
        STRUCT('peso_p5'               AS campo,
               TO_JSON_STRING(j.a.peso_p5) AS agora,
               TO_JSON_STRING(j.b.peso_p5) AS antes),
        STRUCT('n_p10'               AS campo,
               TO_JSON_STRING(j.a.n_p10) AS agora,
               TO_JSON_STRING(j.b.n_p10) AS antes),
        STRUCT('a_odd_dava_p10'               AS campo,
               TO_JSON_STRING(j.a.a_odd_dava_p10) AS agora,
               TO_JSON_STRING(j.b.a_odd_dava_p10) AS antes),
        STRUCT('aconteceu_p10'               AS campo,
               TO_JSON_STRING(j.a.aconteceu_p10) AS agora,
               TO_JSON_STRING(j.b.aconteceu_p10) AS antes),
        STRUCT('diferenca_p10'               AS campo,
               TO_JSON_STRING(j.a.diferenca_p10) AS agora,
               TO_JSON_STRING(j.b.diferenca_p10) AS antes),
        STRUCT('peso_p10'               AS campo,
               TO_JSON_STRING(j.a.peso_p10) AS agora,
               TO_JSON_STRING(j.b.peso_p10) AS antes)
    ]) AS c
    WHERE NOT j.so_no_atual AND NOT j.so_no_anterior
),

divergencias AS (
    SELECT * FROM por_campo WHERE agora IS DISTINCT FROM antes
),

resumo AS (
    SELECT
        'resumo' AS bloco,
        j.celula,
        CAST(NULL AS STRING) AS mercado,
        CAST(NULL AS STRING) AS premissa,
        CAST(NULL AS STRING) AS benchmark,
        CAST(NULL AS STRING) AS campo,
        CAST(NULL AS STRING) AS agora,
        CAST(NULL AS STRING) AS antes,
        COUNT(*)                                        AS linhas,
        COUNTIF(j.so_no_atual OR j.so_no_anterior)      AS sem_contraparte,
        (SELECT COUNT(DISTINCT FORMAT('%s|%s|%s', mercado, premissa, benchmark))
         FROM divergencias AS d WHERE d.celula = j.celula) AS linhas_divergentes,
        (SELECT COUNT(*) FROM divergencias AS d WHERE d.celula = j.celula) AS campos_divergentes,
        30 * COUNTIF(NOT j.so_no_atual AND NOT j.so_no_anterior)
                                                        AS campos_comparados
    FROM juntado AS j
    GROUP BY j.celula
),

detalhe AS (
    SELECT
        IF(j.so_no_atual, 'so_no_atual', 'so_no_anterior') AS bloco,
        j.celula, j.mercado, j.premissa, j.benchmark,
        CAST(NULL AS STRING) AS campo,
        CAST(NULL AS STRING) AS agora,
        CAST(NULL AS STRING) AS antes,
        NULL AS linhas, NULL AS sem_contraparte, NULL AS linhas_divergentes,
        NULL AS campos_divergentes, NULL AS campos_comparados
    FROM juntado AS j
    WHERE j.so_no_atual OR j.so_no_anterior

    UNION ALL

    SELECT
        'campo_divergente' AS bloco,
        celula, mercado, premissa, benchmark, campo, agora, antes,
        NULL, NULL, NULL, NULL, NULL
    FROM divergencias
)

SELECT * FROM resumo
UNION ALL
SELECT * FROM detalhe
ORDER BY bloco, celula, mercado, premissa, benchmark, campo