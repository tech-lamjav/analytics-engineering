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
*/

{%- set universo = taskf_universo_valido(var('taskf_universo', 'completo')) -%}

{%- set pisos = taskf_pisos() -%}
{# As quatro que a spec #49 nomeia. Digitadas porque é uma lista da spec, não algo a derivar do
   dado: uma regra que descobrisse sozinha "as de maior sinal" concordaria com o que quer que o
   número estivesse dizendo hoje. #}
{%- set as_quatro = ['clean_sheets_altos', 'superioridade_xg', 'tende_golear', 'defesa_forte'] -%}
{# A régua, num lugar só. #}
{%- set piso_veredito = 5  -%}
{%- set n_minimo      = 25 -%}
{# As células de "histórico real" — as de escopo solto. Derivadas do 2×2, não digitadas: o nome de
   célula sai sempre de taskf_nomes_de_celula(). #}
{%- set cel_escopo = taskf_nomes_de_celula()['todas|temporada'] -%}
{%- set cel_ambos  = taskf_nomes_de_celula()['todas|ultimos_10'] -%}
{%- set cel_base   = taskf_nomes_de_celula()['da_competicao|temporada'] -%}
{%- set cel_recorte = taskf_nomes_de_celula()['da_competicao|ultimos_10'] -%}


WITH medido AS (
    SELECT *
    FROM {{ source('futebol_taskF', 'taskf_teste2') }}
    WHERE universo = '{{ universo }}'
      AND usado_para_peso
),

{# Uma linha por premissa, com as quatro células lado a lado. O grão do Teste 2 é (mercado,
   premissa, benchmark), e o agrupamento aqui carrega o mercado junto porque supor unicidade de
   NOME é como se descobre que ela não valia.

   ⚠️ E ela não vale: `defesas_vazaveis` existe em DOIS mercados — BTTS (consenso) e Gols (sharp)
   —, com vereditos OPOSTOS. As "39 premissas" do entregável são 39 linhas de (mercado, premissa,
   benchmark) sobre 38 nomes distintos. Este cabeçalho dizia o contrário até a medição da #58
   desmenti-lo; a expectativa fica registrada, corrigida, porque é ela que explica por que o
   agrupamento não é por nome. Quem agrupar só por `premissa` mistura as duas linhas e produz um
   veredito que não é de nenhuma das duas. #}
por_premissa AS (
    SELECT
        mercado,
        premissa,
        benchmark,
        {%- for cel in [cel_base, cel_escopo, cel_recorte, cel_ambos] %}
        MAX(IF(celula = '{{ cel }}', diferenca_p{{ piso_veredito }}, NULL)) AS dif_{{ cel }},
        MAX(IF(celula = '{{ cel }}', n_p{{ piso_veredito }},         NULL)) AS n_{{ cel }},
        MAX(IF(celula = '{{ cel }}', peso_p{{ piso_veredito }},      NULL)) AS peso_{{ cel }},
        MAX(IF(celula = '{{ cel }}', pct_amostra_curta,              NULL)) AS curta_{{ cel }},
        {%- endfor %}
        {%- for piso in pisos %}
        MAX(IF(celula = '{{ cel_escopo }}', diferenca_p{{ piso }}, NULL)) AS dif_escopo_p{{ piso }},
        MAX(IF(celula = '{{ cel_ambos }}',  diferenca_p{{ piso }}, NULL)) AS dif_ambos_p{{ piso }},
        {%- endfor %}
        COUNT(DISTINCT celula) AS celulas
    FROM medido
    GROUP BY mercado, premissa, benchmark
),

{# A regra, aplicada. Uma premissa que não acende numa das duas células de histórico real cai no
   primeiro WHEN — a diferença dela ali é NULL — e sai SEM_EVIDENCIA por ausência de medida, não
   por sinal negativo. O teste de NULL vem PRIMEIRO de propósito: em SQL, `NULL > 0` é NULL e não
   FALSE, então sem ele a linha escorregaria até o ELSE e sairia com o mesmo rótulo pelo motivo
   errado. A contagem `celulas` viaja junto e sai no detalhe: ela é o diagnóstico de quantas das
   quatro a premissa alcançou, e é o que distingue os dois casos ao ler a saída. #}
julgado AS (
    SELECT
        p.*,
        p.premissa IN ({{ as_quatro | map('tojson') | join(', ') }}) AS uma_das_quatro,
        CASE
            WHEN p.dif_{{ cel_escopo }} IS NULL OR p.dif_{{ cel_ambos }} IS NULL
                THEN 'SEM_EVIDENCIA'
            WHEN p.dif_{{ cel_escopo }} > 0 AND p.dif_{{ cel_ambos }} > 0
                 AND p.n_{{ cel_escopo }} >= {{ n_minimo }}
                 AND p.n_{{ cel_ambos }}  >= {{ n_minimo }}
                THEN 'SOBREVIVE'
            WHEN p.dif_{{ cel_escopo }} > 0 AND p.dif_{{ cel_ambos }} > 0
                THEN 'SOBREVIVE_COM_RESSALVA'
            ELSE 'SEM_EVIDENCIA'
        END AS veredito
    FROM por_premissa AS p
)

SELECT 1 AS ordem, 'quatro' AS bloco,
    premissa AS chave,
    veredito,
    dif_{{ cel_escopo }} AS dif_escopo,
    dif_{{ cel_ambos }}  AS dif_ambos,
    CAST(n_{{ cel_escopo }} AS FLOAT64) AS n_escopo,
    TO_JSON_STRING(STRUCT(
        mercado, benchmark, celulas,
        dif_{{ cel_base }}    AS dif_base,    n_{{ cel_base }}    AS n_base,
        dif_{{ cel_recorte }} AS dif_recorte, n_{{ cel_recorte }} AS n_recorte,
        n_{{ cel_ambos }} AS n_ambos,
        peso_{{ cel_base }} AS peso_base, peso_{{ cel_escopo }} AS peso_escopo,
        peso_{{ cel_recorte }} AS peso_recorte, peso_{{ cel_ambos }} AS peso_ambos,
        curta_{{ cel_base }} AS curta_base, curta_{{ cel_escopo }} AS curta_escopo,
        curta_{{ cel_recorte }} AS curta_recorte, curta_{{ cel_ambos }} AS curta_ambos,
        {%- for piso in pisos %}
        dif_escopo_p{{ piso }}, dif_ambos_p{{ piso }}{{ ',' if not loop.last }}
        {%- endfor %}
    )) AS detalhe
FROM julgado
WHERE uma_das_quatro

UNION ALL
{# O resumo do catálogo: quantas das 39 caem em cada veredito, e quem são. É o que impede a
   leitura "duas das quatro sobreviveram" de ser lida sem saber que o catálogo inteiro tem N
   sobreviventes. #}
SELECT 2, 'catalogo',
    veredito,
    FORMAT('%d de %d premissas', COUNT(*), (SELECT COUNT(*) FROM julgado)),
    CAST(COUNT(*) AS FLOAT64),
    CAST(COUNTIF(uma_das_quatro) AS FLOAT64),
    ROUND(AVG(dif_{{ cel_escopo }}), 2),
    TO_JSON_STRING(STRUCT(
        STRING_AGG(premissa, ', ' ORDER BY premissa) AS quais,
        STRING_AGG(IF(uma_das_quatro, premissa, NULL), ', ' ORDER BY premissa) AS quais_das_quatro,
        {{ piso_veredito }} AS piso_do_veredito, {{ n_minimo }} AS n_minimo,
        '{{ universo }}' AS universo
    ))
FROM julgado
GROUP BY veredito

ORDER BY ordem, chave
