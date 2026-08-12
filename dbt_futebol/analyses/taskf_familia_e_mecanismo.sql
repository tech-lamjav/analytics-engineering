/*
    [F-4] O EFEITO DO EIXO DE ESCOPO QUEBRADO POR FAMÍLIA DE COMPETIÇÃO — e, antes disso, a prova
    de quais famílias sequer têm amostra na janela congelada.

    A #53 pede o efeito separado em `ano_calendario` e `split_year` (spec #49, user story 12). A
    razão é que na JANELA MEDIDA as duas se comportam de maneira diferente sob o eixo de escopo:
    numa split-year o rótulo de `season` vira no meio do ano, e como o eixo de escopo não toca o
    filtro `l.season = a.season`, o histórico doméstico do time continua cortado — só a célula
    `ambos` o alcança. A classificação é derivada do calendário pela macro
    taskf_familia_competicao(); o critério e as armadilhas dele estão no cabeçalho de lá.

    ⚠️ ANTES DE LER O EFEITO, LEIA A COMPOSIÇÃO. "Efeito nulo numa família" e "família sem
    amostra" são coisas diferentes e a segunda é a que se espera aqui: a #51 já mediu que os
    únicos jogos de Champions da janela são os 8 de 04/08 à noite, que o teto do universo
    congelado remove. Uma célula vazia da quebra tem de ser lida como SEM AMOSTRA, nunca como
    "juntar campeonato não muda nada para as europeias" — a janela congelada (16/06 a 04/08) cai
    inteira na virada de temporada, e é por isso que ela é o pior lugar possível para medir
    split-year. As linhas de competição fora do universo saem com `jogos_no_universo = 0` de
    propósito: a ausência é o achado, e escondê-la faria a quebra parecer completa.

    ────────────────────────────────────────────────────────────────────────────────
    TRÊS COISAS NA MESMA SAÍDA, com a coluna `nivel` separando os grãos:

      nivel = 'competicao'  uma linha por competição EXISTENTE (as 13, não só as do universo),
                            com a família e a evidência que a classificou ao lado.
      nivel = 'familia'     o rollup por família.
      nivel = 'total'       o universo inteiro, que serve de denominador e de conferência.

    Somar linhas de níveis diferentes conta o mesmo jogo duas vezes — filtre `nivel` sempre.

    O MECANISMO é medido no carimbo por célula (`taskf_pit_por_celula`), não em `apostas`: são as
    partidas anteriores que cada par (jogo, time) ganhou ao soltar a competição. `min_jogos` do
    jogo é o MENOR `played_total` entre os dois times — a mesma definição do task01_base(), porque
    as premissas comparam os dois lados. As contagens de piso mostram quantos jogos do universo
    passam a satisfazer cada corte da varredura com o histórico junto (user story 5 da spec).

    ⚠️ De onde vem cada metade. O UNIVERSO (quais jogos e quais linhas de aposta) sai do
    task01_base() sobre a camada de premissas MATERIALIZADA AGORA, então esta análise deve rodar
    com as duas células já carimbadas — a corrente é a última que rodou. O EFEITO sai do carimbo,
    que tem as duas células gravadas e não depende de qual está materializada. Que o universo seja
    idêntico nas quatro células é invariante da Costura B (#55); aqui ele é reportado
    (`jogos_no_universo`) e tem de bater com as duas linhas correspondentes do `taskf_teste2`.

    COMO RODAR (do dbt_futebol/), depois de as DUAS células terem sido carimbadas:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_familia_e_mecanismo
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_familia_e_mecanismo.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set carimbos = 'smartbetting-dados.futebol_taskF.taskf_pit_por_celula' -%}
{%- set pisos    = [3, 5, 10] -%}

WITH {{ task01_base() }},

{{ taskf_familia_competicao() }},

apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE {{ taskf_universo_filtro() }}
),

universo_por_competicao AS (
    SELECT
        competition,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*)                   AS linhas_no_universo
    FROM apostas_congeladas
    GROUP BY competition
),

fixtures_do_universo AS (
    SELECT DISTINCT fixture_id FROM apostas_congeladas
),

{#- INNER JOIN de propósito: par que existe numa célula e não na outra é assunto da
    analyses/taskf_monotonicidade_escopo.sql, que o mede nos dois sentidos e emite veredito. Aqui
    ele seria ruído silencioso dentro de uma média. -#}
pares AS (
    SELECT
        b.fixture_id,
        b.team_id,
        b.competition,
        b.played_total AS played_base,
        e.played_total AS played_escopo
    FROM (SELECT * FROM `{{ carimbos }}` WHERE celula = 'base')   AS b
    JOIN (SELECT * FROM `{{ carimbos }}` WHERE celula = 'escopo') AS e
      USING (fixture_id, team_id)
    JOIN fixtures_do_universo USING (fixture_id)
),

por_fixture AS (
    SELECT
        fixture_id,
        ANY_VALUE(competition) AS competition,
        MIN(played_base)       AS min_jogos_base,
        MIN(played_escopo)     AS min_jogos_escopo
    FROM pares
    GROUP BY fixture_id
),

mecanismo_por_competicao AS (
    SELECT
        competition,
        COUNT(*)                                     AS pares,
        COUNTIF(played_escopo > played_base)         AS pares_com_ganho,
        SUM(played_escopo - played_base)             AS soma_do_ganho,
        MAX(played_escopo - played_base)             AS ganho_max
    FROM pares
    GROUP BY competition
),

piso_por_competicao AS (
    SELECT
        competition
        {%- for piso in pisos %},
        COUNTIF(min_jogos_base   >= {{ piso }})      AS jogos_min{{ piso }}_base,
        COUNTIF(min_jogos_escopo >= {{ piso }})      AS jogos_min{{ piso }}_escopo,
        COUNTIF(min_jogos_base <  {{ piso }}
                AND min_jogos_escopo >= {{ piso }})  AS jogos_cruzam_piso{{ piso }}
        {%- endfor %}
    FROM por_fixture
    GROUP BY competition
),

{#- Uma linha por competição EXISTENTE, com zeros onde o universo não alcança. A família vem da
    esquerda porque é ela que tem as 13; o universo e o mecanismo entram por LEFT JOIN. -#}
por_competicao AS (
    SELECT
        f.competition,
        f.competition_id,
        f.familia,
        f.temporadas_observadas,
        f.temporadas_atravessando,
        DATE(f.primeiro_kickoff)                 AS primeiro_kickoff,
        DATE(f.ultimo_kickoff)                   AS ultimo_kickoff,
        COALESCE(u.jogos_no_universo, 0)         AS jogos_no_universo,
        COALESCE(u.linhas_no_universo, 0)        AS linhas_no_universo,
        COALESCE(m.pares, 0)                     AS pares,
        COALESCE(m.pares_com_ganho, 0)           AS pares_com_ganho,
        COALESCE(m.soma_do_ganho, 0)             AS soma_do_ganho,
        m.ganho_max                              AS ganho_max
        {%- for piso in pisos %},
        COALESCE(p.jogos_min{{ piso }}_base, 0)     AS jogos_min{{ piso }}_base,
        COALESCE(p.jogos_min{{ piso }}_escopo, 0)   AS jogos_min{{ piso }}_escopo,
        COALESCE(p.jogos_cruzam_piso{{ piso }}, 0)  AS jogos_cruzam_piso{{ piso }}
        {%- endfor %}
    FROM familia_competicao       AS f
    LEFT JOIN universo_por_competicao  AS u USING (competition)
    LEFT JOIN mecanismo_por_competicao AS m USING (competition)
    LEFT JOIN piso_por_competicao      AS p USING (competition)
),

{#- Os rollups somam o grão de competição em vez de reagregar o dado bruto: contagem é aditiva, e
    a média sai de soma/pares no fim — reagregar seria uma segunda definição do mesmo número. -#}
{%- set metricas %}
        SUM(jogos_no_universo)   AS jogos_no_universo,
        SUM(linhas_no_universo)  AS linhas_no_universo,
        SUM(pares)               AS pares,
        SUM(pares_com_ganho)     AS pares_com_ganho,
        SUM(soma_do_ganho)       AS soma_do_ganho,
        MAX(ganho_max)           AS ganho_max
        {%- for piso in pisos %},
        SUM(jogos_min{{ piso }}_base)    AS jogos_min{{ piso }}_base,
        SUM(jogos_min{{ piso }}_escopo)  AS jogos_min{{ piso }}_escopo,
        SUM(jogos_cruzam_piso{{ piso }}) AS jogos_cruzam_piso{{ piso }}
        {%- endfor %}
{%- endset %}

empilhado AS (
    SELECT
        'competicao' AS nivel, 1 AS nivel_ord, competition AS chave, familia,
        competition_id, temporadas_observadas, temporadas_atravessando,
        primeiro_kickoff, ultimo_kickoff,
        jogos_no_universo, linhas_no_universo, pares, pares_com_ganho, soma_do_ganho, ganho_max
        {%- for piso in pisos %},
        jogos_min{{ piso }}_base, jogos_min{{ piso }}_escopo, jogos_cruzam_piso{{ piso }}
        {%- endfor %}
    FROM por_competicao

    UNION ALL

    {#- Os NULL dos rollups são CASTADOS: sem o cast o literal entra como INT64 e a união com uma
        coluna DATE falha por falta de supertipo comum. -#}
    SELECT
        'familia', 2, familia, familia,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS DATE),  CAST(NULL AS DATE),
        {{ metricas }}
    FROM por_competicao
    GROUP BY familia

    UNION ALL

    SELECT
        'total', 3, 'TODAS', CAST(NULL AS STRING),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS DATE),  CAST(NULL AS DATE),
        {{ metricas }}
    FROM por_competicao
)

SELECT
    nivel,
    chave,
    familia,
    competition_id,
    temporadas_observadas,
    temporadas_atravessando,
    primeiro_kickoff,
    ultimo_kickoff,
    jogos_no_universo,
    ROUND(SAFE_DIVIDE(jogos_no_universo,
                      SUM(IF(nivel = 'total', jogos_no_universo, 0)) OVER ()) * 100, 1)
                                                              AS pct_do_universo,
    linhas_no_universo,
    pares,
    pares_com_ganho,
    ROUND(SAFE_DIVIDE(pares_com_ganho, pares) * 100, 1)       AS pct_pares_com_ganho,
    ROUND(SAFE_DIVIDE(soma_do_ganho, pares), 2)               AS ganho_medio_por_par,
    ganho_max
    {%- for piso in pisos %},
    jogos_min{{ piso }}_base,
    jogos_min{{ piso }}_escopo,
    jogos_cruzam_piso{{ piso }}
    {%- endfor %}
FROM empilhado
ORDER BY nivel_ord, jogos_no_universo DESC, chave
