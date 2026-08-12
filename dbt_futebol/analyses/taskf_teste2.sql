/*
    [F-2] O TESTE 2 da task [F] — o mesmo do [0.1], sobre o universo congelado, com coluna de
    célula. É a saída que a Costura B (#55) vai testar e de onde saem as 39 linhas do entregável.

        diferença = média(acerto | premissa acesa) − média(prob justa | premissa acesa)

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ESTA ANÁLISE É UM SCRIPT DDL, E NÃO UM MODELO dbt

    Um modelo segue o target, e o target default é `dev`, que aponta para o dataset de PRODUÇÃO
    (`futebol`) — o mesmo que `prod`. Um `dbt build` distraído publicaria medição no board. O
    destino aqui está escrito no SQL, fixo em `futebol_taskF`, e por isso não tem como escorregar.
    Mesmo argumento e mesmo padrão do analyses/taskf_congela_baseline.sql. Ver ADR 0007.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE A AGREGAÇÃO É UMA CÓPIA DO analyses/task01_teste2.sql

    Copiar código costuma ser o erro que a ADR 0007 recusou nos modelos de premissas — lá a cópia
    derivaria da produção em silêncio. Aqui a assimetria é outra: o original não é código vivo, é
    o REGISTRO CONGELADO de uma task encerrada ([0.1], PR #11), e ninguém o edita. O que a cópia
    precisa reproduzir é um cálculo parado, não um que anda.

    E a cópia não é acreditada, é verificada: a reconciliação da célula `base` contra os números
    publicados (analyses/taskf_reconciliacao_01.sql) é exatamente o teste de que ela computa a
    mesma coisa — nos mesmos dados para os quais foi copiada. Extrair a agregação para um macro
    compartilhado teria o custo oposto e maior: mexer no artefato que produziu os números de
    referência, com o risco de reconciliar a medição contra um bug meu.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE MUDA EM RELAÇÃO AO ORIGINAL — três coisas, e só três:

    1. UNIVERSO CONGELADO. `apostas` é recortada por taskf_universo_filtro(). O original rodou sem
       corte (a janela dele é o instante da execução). Ver macros/taskf_universo.sql: o teto é um
       INSTANTE, não um dia, e é isso que devolve os 169 publicados em vez de 178.
    2. COLUNA DE CÉLULA, mais os dois eixos ao lado dela e o carimbo de quando/de-qual-commit.
       O rótulo é DERIVADO dos eixos por taskf_celula() — nunca digitado. Uma célula não tem como
       ser gravada com o nome de outra.
    3. PISO 3 acrescentado à varredura, que no original é [0, 5, 10]. É o que a spec #49 pede
       ("piso varrido em [0, 3, 5, 10] ... para distinguir achado de escolha de corte"). Entra
       agora porque é este ticket que define o formato da tabela, e mudar formato depois da #55
       ter testes em cima dele custa mais. A reconciliação compara só 0/5/10, que é o que a [0.1]
       publicou.

    Fora isso a agregação é a do original, incluindo o grão (mercado, premissa, BENCHMARK) — as
    linhas de consenso do Handicap e do Gols continuam saindo marcadas `usado_para_peso = false`,
    porque o ROI delas é muito pior que o das sharp e essa diferença é sobre QUAIS jogos a
    Pinnacle escolhe precificar, não sobre o benchmark.

    ────────────────────────────────────────────────────────────────────────────────
    ACUMULATIVA POR CÉLULA. A tabela é criada uma vez e cada execução substitui SÓ a sua célula
    (DELETE + INSERT). As quatro convivem, que é o que a Costura B precisa. O schema é escrito
    por extenso de propósito: ele é o contrato que as células seguintes (#53, #54) têm de cumprir,
    e um INSERT de formato diferente falha alto em vez de alargar a tabela em silêncio.

    ⚠️ `medido_em` existe porque a spec exige que as quatro células rodem na MESMA EXECUÇÃO — o
    baseline não é reaproveitado justamente porque `linha_subindo`/`linha_descendo` leem odds ao
    vivo e viram sozinhas entre builds. Com o carimbo, "mesma execução" é conferível na tabela; sem
    ele, é confiança. Quem escreve a Costura B (#55) precisa dele, e a forma verificável é:
    `fact_odds_snapshot.dbt_loaded_at` ANTERIOR aos quatro `medido_em`. Isso prova o que de fato
    importa — que as quatro leram a MESMA construção dos fatos —, que é mais forte do que os
    quatro carimbos serem próximos entre si.

    ────────────────────────────────────────────────────────────────────────────────
    COMO RODAR (do dbt_futebol/) — DUAS FASES, e a separação não é economia, é correção.

    FASE 1, uma vez só para as quatro células: a ancestria inteira, que é o que popula o dataset
    de medição. Com `--target taskF` todo `ref()` resolve para futebol_taskF, então os fatos têm
    de existir lá antes.

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
        --select +int_futebol_premissas_1x2 +int_futebol_premissas_ou +int_futebol_premissas_ah \
                 +int_futebol_premissas_btts +int_futebol_premissas_dc +int_futebol_corroboracao

    FASE 2, uma vez POR CÉLULA: só os nós que respondem às vars — o PIT e os cinco modelos de
    premissas. Nada de `+`.

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
        --select int_futebol_team_form_pit int_futebol_premissas_1x2 int_futebol_premissas_ou \
                 int_futebol_premissas_ah int_futebol_premissas_btts int_futebol_premissas_dc \
        --vars '{pit_escopo: todas}'        # a célula; ausente = base

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_teste2 \
        --vars '{taskf_git_sha: '"$(git rev-parse --short HEAD)"', pit_escopo: todas}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_teste2.sql

    ⚠️ NÃO use `+` na fase 2. O `+` reconstrói o `fact_odds_snapshot` a partir do NDJSON da landing
    a cada célula, e aí as quatro deixam de ler a mesma construção dos fatos. O argumento que
    sustenta a comparação entre células — um viés comum às quatro cancela — vale exatamente
    porque elas leem UMA construção. Reconstruir por célula reinjeta entre elas a mesma variação
    de 2 linhas que a reconciliação da `base` encontrou, e aí ela deixa de cancelar e passa a ser
    lida como efeito de escopo. É também um rescan completo do NDJSON por célula, sem ganho.

    ⚠️ Nas células de escopo juntado, duas guardas ficam vermelhas POR DESENHO — elas afirmam
    coisa da célula `base`. Ver o cabeçalho de tests/assert_taskf_pit_default_igual_baseline.sql:

      --exclude assert_taskf_pit_default_igual_baseline assert_pit_first_game_has_no_history

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set c      = taskf_celula() -%}
{%- set j      = taskf_universo() -%}
{%- set pisos  = [0, 3, 5, 10] -%}
{%- set tabela = 'smartbetting-dados.futebol_taskF.taskf_teste2' -%}

{#- Uma lista, três usos: o DDL, a lista de colunas do INSERT e a ordem da projeção. Escrita duas
    vezes, ela derivaria — e um INSERT posicional com colunas trocadas de lugar não dá erro, dá
    número errado. -#}
{%- set colunas = [
    'celula STRING', 'pit_escopo STRING', 'pit_recorte STRING',
    'medido_em TIMESTAMP', 'git_sha STRING',
    'janela_ini DATE', 'janela_fim DATE',
    'jogos_no_universo INT64', 'linhas_no_universo INT64',
    'mercado STRING', 'premissa STRING', 'benchmark STRING', 'usado_para_peso BOOL',
    'fator_encolhimento FLOAT64', 'jogos_medios FLOAT64', 'pct_amostra_curta FLOAT64'
] -%}
{%- for piso in pisos -%}
    {%- set _ = colunas.extend([
        'n_p' ~ piso ~ ' INT64',
        'a_odd_dava_p' ~ piso ~ ' FLOAT64',
        'aconteceu_p' ~ piso ~ ' FLOAT64',
        'diferenca_p' ~ piso ~ ' FLOAT64',
        'peso_p' ~ piso ~ ' FLOAT64'
    ]) -%}
{%- endfor -%}
{%- set _ = colunas.append('peso_p0_k0 FLOAT64') -%}
{%- set nomes_colunas = [] -%}
{%- for col in colunas -%}
    {%- set _ = nomes_colunas.append(col.split(' ')[0]) -%}
{%- endfor -%}


CREATE TABLE IF NOT EXISTS `{{ tabela }}` (
    {{ colunas | join(',\n    ') }}
);


DELETE FROM `{{ tabela }}` WHERE celula = '{{ c.nome }}';


INSERT INTO `{{ tabela }}` ({{ nomes_colunas | join(', ') }})

WITH {{ task01_base() }},

{#- O UNIVERSO CONGELADO. Por que o recorte cai aqui, em cima de `apostas`, e não num parâmetro
    novo do task01_base(): está no cabeçalho de macros/taskf_universo.sql, junto do predicado. -#}
apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE {{ taskf_universo_filtro() }}
),

{#- Uma passada, grão (mercado, premissa, benchmark). Só as linhas em que a premissa ACENDEU
    entram nas médias — é essa a definição do Teste 2.

    O PISO DE AMOSTRA entra como COLUNA, não como execução separada, porque o encolhimento (`k`) e
    o piso tratam eixos DIFERENTES: `k` trata `n` pequeno (a premissa acendeu poucas vezes), o
    piso trata jogo sem histórico. `clean_sheets_altos` tem n=105 (grande, o encolhimento mal
    encosta) e 77% das linhas em jogo com menos de 5 partidas disputadas — a assinatura exata do
    artefato que matou os +9,7% da Task [0]. Ver os dois lado a lado é o ponto. -#}
agregado AS (
    SELECT
        a.market_id,
        pl.premissa,
        a.benchmark,
        AVG(IF(pl.acesa, a.min_jogos, NULL))                     AS jogos_medios,
        AVG(IF(pl.acesa, IF(a.min_jogos < 5, 1.0, 0.0), NULL))   AS frac_curta
        {%- for piso in pisos %},
        COUNTIF(pl.acesa AND a.min_jogos >= {{ piso }})          AS n_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos >= {{ piso }},
               a.prob_justa_fechamento, NULL))                   AS p_odd_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos >= {{ piso }},
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_{{ piso }}
        {%- endfor %}
    FROM apostas_congeladas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    GROUP BY a.market_id, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
),

janela AS (
    SELECT
        MIN(DATE(kickoff_utc))     AS janela_ini,
        MAX(DATE(kickoff_utc))     AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*)                   AS linhas_no_universo
    FROM apostas_congeladas
),

{#- `preferido` calculado UMA vez, não repetido em cada coluna que depende dele. -#}
rotulado AS (
    SELECT
        g.*,
        CASE g.market_id
            {%- for mid, m in task01_markets().items() %}
            WHEN {{ mid }} THEN '{{ m.nome }}'
            {%- endfor %}
        END AS mercado,
        g.benchmark = CASE g.market_id
                          WHEN 12 THEN 'derivada'
                          WHEN 8  THEN 'consenso'
                          ELSE         'sharp'
                      END AS preferido
    FROM agregado AS g
)

SELECT
    '{{ c.nome }}'                                          AS celula,
    '{{ c.escopo }}'                                        AS pit_escopo,
    '{{ c.recorte }}'                                       AS pit_recorte,
    CURRENT_TIMESTAMP()                                     AS medido_em,
    '{{ var("taskf_git_sha", "desconhecido") }}'            AS git_sha,
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    j.linhas_no_universo,
    r.mercado,
    r.premissa,
    r.benchmark,
    r.preferido                                             AS usado_para_peso,
    -- Fator de encolhimento aplicado ao peso: n/(n+50). Exposto em vez de um flag binário de "n
    -- suficiente" porque o corte seria arbitrário e este número já diz exatamente quanto da
    -- medição sobreviveu. `desfalque_adversario` (n=7) fica em 0,12: qualquer sinal que ela
    -- tivesse seria 88% descartado por falta de amostra, e isso é diferente de "medimos e deu
    -- ruim".
    ROUND(SAFE_DIVIDE(r.n_0, r.n_0 + 50), 2)                AS fator_encolhimento,
    ROUND(r.jogos_medios, 1)                                AS jogos_medios,
    ROUND(r.frac_curta * 100, 1)                            AS pct_amostra_curta
    {%- for piso in pisos %},
    r.n_{{ piso }}                                          AS n_p{{ piso }},
    ROUND(r.p_odd_{{ piso }}  * 100, 1)                     AS a_odd_dava_p{{ piso }},
    ROUND(r.p_real_{{ piso }} * 100, 1)                     AS aconteceu_p{{ piso }},
    ROUND((r.p_real_{{ piso }} - r.p_odd_{{ piso }}) * 100, 1) AS diferenca_p{{ piso }},
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso negativo: com
    -- esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_{{ piso }} - r.p_odd_{{ piso }}) * 100, 0)
             * SAFE_DIVIDE(r.n_{{ piso }}, r.n_{{ piso }} + 50), 2),
       NULL)                                                AS peso_p{{ piso }}
    {%- endfor %},
    -- Sensibilidade: peso sem encolhimento nenhum, no piso 0. Mostra o quanto o k=50 está
    -- segurando.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_0 - r.p_odd_0) * 100, 0), 2),
       NULL)                                                AS peso_p0_k0
FROM rotulado AS r
CROSS JOIN janela AS j
