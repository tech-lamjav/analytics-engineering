/*
    [F-4] O NÚMERO DE CADA PREMISSA, LADO A LADO, ENTRE DUAS CÉLULAS. Por default `base` contra
    `escopo`, que é a comparação que a #53 pede: a primeira célula que produz número novo.

    A tabela do entregável final (as 39 linhas da #59) sai desta comparação repetida para as
    outras células; aqui ela é o que responde "o que o número vira quando junta" para o eixo de
    escopo isolado.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE ESPERAR, ANTES DE OLHAR — para o resultado poder desmentir algo:

    1. As TRÊS PREMISSAS DE TABELA do catálogo medido (`superioridade_tabela`, `supremacia`,
       `sem_rodizio`) têm de sair IDÊNTICAS NO PISO 0. A ADR 0008 as mantém competição-scoped em
       todas as células: rank e ppg saem do agregado próprio do team_form_pit, que não segue os
       eixos. Se uma delas se mexer no piso 0, a ADR 0008 não está implementada como diz.
       (A quarta que a ADR nomeia, `x_superioridade_tabela`, não é premissa medida: é coluna
       interna do 1X2 que a Dupla Chance reusa dentro do `lado_coberto_forte`, o qual TAMBÉM lê
       `forca_mismatch` e portanto segue o eixo.)

    2. ⚠️ IDÊNTICAS NO PISO 0, NÃO NOS DEMAIS PISOS. O `min_jogos` segue a célula inclusive nas
       linhas dessas três — é a seção "Consequences" da própria ADR 0008: o piso é propriedade do
       jogo, não da premissa. Com o histórico junto, jogos que não passavam no piso 5 passam a
       passar, então `n_p5` e `diferenca_p5` mudam mesmo com a premissa imóvel. O mesmo vale para
       `jogos_medios` e `pct_amostra_curta`, que não têm piso e leem o `min_jogos` da célula.
       Por isso o veredito das três olha SÓ o piso 0: exigir igualdade nos demais seria cobrar da
       ADR 0008 uma coisa que ela explicitamente não promete.

    3. `historico_over`, `historico_under`, `historico_btts`, `historico_seco` e as duas de xG
       leem histórico competição-scoped PRÓPRIO, fora do team_form_pit (#52), e por isso TÊM de
       se mexer. Se elas não se mexerem, o eixo não alcançou todas as fontes e a célula está
       misturada.

    4. `h2h_favoravel` (1X2) é a ÚNICA imune por definição: o `fact_h2h` já cruza campeonatos hoje
       e a spec o deixa como está — "é a única fonte imune ao efeito medido" (#49). Ela só pode
       mudar via piso: `n_p5` para cima, `diferenca_p0` parada.

       ⚠️ `adversario_limitado` (DC) NÃO é imune, embora reuse o h2h. A premissa é
       `o_aproveitamento < 45 OR x_h2h_favoravel`, e `o_aproveitamento` sai de
       `wins_total/draws_total/played_total` do PIT — que seguem o eixo. Medido entre `base` e
       `escopo`: `n_p0` 160 → 165 e `diferenca_p0` +0,7 → +1,2. Uma premissa que reusa fonte imune
       só herda a imunidade se **todos** os seus insumos forem imunes; aqui o OR basta para
       quebrá-la. Esta linha esteve errada no primeiro commit desta análise e foi corrigida com o
       número que a desmentiu — a expectativa existe para poder ser falsificada, e foi.

    ────────────────────────────────────────────────────────────────────────────────
    A COMPARAÇÃO É FULL OUTER de propósito: premissa que existe numa célula e não na outra sai
    como `SEM_CONTRAPARTE` em vez de desaparecer do resultado. Uma premissa some da tabela quando
    ela não acende nenhuma vez na célula (o `HAVING COUNTIF(acesa) > 0` do taskf_teste2), e isso é
    achado, não linha a esconder.

    As células a comparar são vars, validadas contra os quatro nomes possíveis — um nome digitado
    errado devolveria zero linha ou uma coluna inteira de `SEM_CONTRAPARTE`, e as duas coisas se
    parecem demais com um resultado.

    COMO RODAR (do dbt_futebol/), depois de as duas células terem sido medidas pelo taskf_teste2:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_delta_celulas
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_delta_celulas.sql

      # outro par de células:
      ... --select taskf_delta_celulas --vars '{taskf_celula_a: base, taskf_celula_b: ambos}'

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set cel_a = var('taskf_celula_a', 'base') -%}
{%- set cel_b = var('taskf_celula_b', 'escopo') -%}
{#- Os quatro nomes vêm da macro que os define, nunca de uma segunda lista digitada aqui: uma
    cópia que precisa ficar igual para sempre não fica, e a divergência seria muda. -#}
{%- set celulas_validas = taskf_nomes_de_celula().values() | list -%}
{%- for c in [cel_a, cel_b] -%}
    {%- if c not in celulas_validas -%}
        {{ exceptions.raise_compiler_error(
            "célula inválida: '" ~ c ~ "'. Valores aceitos: " ~ celulas_validas | join(' | ')) }}
    {%- endif -%}
{%- endfor -%}
{%- if cel_a == cel_b -%}
    {{ exceptions.raise_compiler_error(
        "taskf_celula_a e taskf_celula_b são a mesma célula ('" ~ cel_a ~ "') — nada a comparar.") }}
{%- endif -%}

{%- set pisos = [0, 3, 5, 10] -%}
{#- As premissas de tabela do catálogo medido (ADR 0008). O veredito delas é o piso 0; ver o
    cabeçalho. -#}
{%- set premissas_de_tabela = ['superioridade_tabela', 'supremacia', 'sem_rodizio'] -%}
{#- Campos que, mudando, contam como "a premissa se mexeu". `n_p0` entra porque mudança no
    conjunto de linhas em que a premissa acende é efeito, não ruído. -#}
{%- set campos_piso0 = ['n_p0', 'a_odd_dava_p0', 'aconteceu_p0', 'dif_p0'] -%}

WITH a AS (
    SELECT * FROM {{ source('futebol_taskF', 'taskf_teste2') }} WHERE celula = '{{ cel_a }}'
),
b AS (
    SELECT * FROM {{ source('futebol_taskF', 'taskf_teste2') }} WHERE celula = '{{ cel_b }}'
),

juntado AS (
    SELECT
        mercado,
        premissa,
        benchmark,
        COALESCE(a.usado_para_peso, b.usado_para_peso)  AS usado_para_peso,
        a.celula IS NULL                                AS so_na_b,
        b.celula IS NULL                                AS so_na_a,
        a.jogos_medios        AS jogos_medios_a,       b.jogos_medios        AS jogos_medios_b,
        a.pct_amostra_curta   AS pct_curta_a,          b.pct_amostra_curta   AS pct_curta_b,
        a.fator_encolhimento  AS encolhimento_a,       b.fator_encolhimento  AS encolhimento_b
        {%- for piso in pisos %},
        a.n_p{{ piso }}          AS n_p{{ piso }}_a,          b.n_p{{ piso }}          AS n_p{{ piso }}_b,
        a.diferenca_p{{ piso }}  AS dif_p{{ piso }}_a,        b.diferenca_p{{ piso }}  AS dif_p{{ piso }}_b,
        a.peso_p{{ piso }}       AS peso_p{{ piso }}_a,       b.peso_p{{ piso }}       AS peso_p{{ piso }}_b,
        a.a_odd_dava_p{{ piso }} AS a_odd_dava_p{{ piso }}_a, b.a_odd_dava_p{{ piso }} AS a_odd_dava_p{{ piso }}_b,
        a.aconteceu_p{{ piso }}  AS aconteceu_p{{ piso }}_a,  b.aconteceu_p{{ piso }}  AS aconteceu_p{{ piso }}_b
        {%- endfor %}
    FROM a FULL OUTER JOIN b USING (mercado, premissa, benchmark)
),

classificado AS (
    SELECT
        j.*,
        premissa IN ({{ premissas_de_tabela | map('tojson') | join(', ') }}) AS e_premissa_de_tabela,

        {#- Quantos campos do piso 0 se mexeram. IS DISTINCT FROM p/ NULL contar como igual a
            NULL, e não como divergência. -#}
        ({% for campo in campos_piso0 %}
          IF({{ campo }}_a IS DISTINCT FROM {{ campo }}_b, 1, 0){{ " + " if not loop.last }}
         {%- endfor %})                                     AS campos_piso0_mudados,

        ({% for piso in pisos %}
          IF(n_p{{ piso }}_a IS DISTINCT FROM n_p{{ piso }}_b, 1, 0)
          + IF(dif_p{{ piso }}_a IS DISTINCT FROM dif_p{{ piso }}_b, 1, 0){{ " + " if not loop.last }}
         {%- endfor %}
          + IF(jogos_medios_a IS DISTINCT FROM jogos_medios_b, 1, 0)
          + IF(pct_curta_a IS DISTINCT FROM pct_curta_b, 1, 0))  AS campos_mudados
    FROM juntado AS j
)

SELECT
    mercado,
    premissa,
    benchmark,
    usado_para_peso,
    CASE
        WHEN so_na_a OR so_na_b               THEN 'SEM_CONTRAPARTE'
        WHEN e_premissa_de_tabela
             AND campos_piso0_mudados = 0     THEN 'TABELA_IMOVEL_NO_PISO0'
        WHEN e_premissa_de_tabela             THEN 'TABELA_MEXEU_CONTRA_A_ADR_0008'
        WHEN campos_mudados = 0               THEN 'IDENTICO'
        ELSE                                       'MUDOU'
    END                                       AS veredito,
    campos_mudados,
    campos_piso0_mudados,
    jogos_medios_a, jogos_medios_b,
    ROUND(jogos_medios_b - jogos_medios_a, 1)    AS delta_jogos_medios,
    pct_curta_a, pct_curta_b,
    ROUND(pct_curta_b - pct_curta_a, 1)          AS delta_pct_curta
    {%- for piso in pisos %},
    n_p{{ piso }}_a, n_p{{ piso }}_b, n_p{{ piso }}_b - n_p{{ piso }}_a AS delta_n_p{{ piso }},
    dif_p{{ piso }}_a, dif_p{{ piso }}_b,
    ROUND(dif_p{{ piso }}_b - dif_p{{ piso }}_a, 1)                     AS delta_dif_p{{ piso }}
    {%- endfor %},
    peso_p0_a, peso_p0_b, ROUND(peso_p0_b - peso_p0_a, 2) AS delta_peso_p0,
    peso_p5_a, peso_p5_b, ROUND(peso_p5_b - peso_p5_a, 2) AS delta_peso_p5,
    '{{ cel_a }}' AS celula_a,
    '{{ cel_b }}' AS celula_b
FROM classificado
ORDER BY ABS(COALESCE(dif_p5_b - dif_p5_a, 0)) DESC, mercado, premissa, benchmark
