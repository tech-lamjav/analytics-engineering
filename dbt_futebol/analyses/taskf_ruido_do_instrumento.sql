{#
    [F] RUÍDO DO INSTRUMENTO — quanto o Teste 2 anda entre duas execuções idênticas (issue #92).

    Esta análise existe para responder UMA pergunta, e ela é sobre a RÉGUA, não sobre o dado:
    com o insumo parado e o mesmo SQL, quanto os campos em pontos percentuais do Teste 2 se
    mexem de uma execução para a outra? Esse número é o PISO da tolerância — abaixo dele a
    régua fica vermelha sem que nada tenha divergido.

    A `taskf_tolerancia_pp` foi calibrada em 0,5 pp por uma frase de `docs/TASK01_RESULTADOS.md`
    ("o mercado de Gols anda 0,2–0,4 pp entre execuções sem que nada mude"), e a #78 mostrou que
    parte daquele movimento era ruído de instrumento que já saiu. Daí a remedição.

    ⚠️ AQUELA FRASE MEDIU OUTRA COISA, e isso importa para lê-la. Os 0,2–0,4 pp são deltas de
    ROI do TESTE 3 (`docs/TASK01_RESULTADOS.md`, ticket #4): a porta "N+ premissas" é um limiar,
    e 0,07% das linhas trocando de lado moveu o ROI do mercado em 0,4 pp. A `taskf_tolerancia_pp`
    governa os campos por premissa do TESTE 2, que são médias, não um agregado atrás de um
    limiar. A régua nasceu calibrada por uma métrica diferente da que ela mede — e é por isso que
    remedir vale mesmo que o número não mude.

    ────────────────────────────────────────────────────────────────────────────────
    AS DUAS CAMADAS, E POR QUE SÓ UMA DELAS É MEDIDA AQUI

    Uma re-medição do Teste 2 tem dois pontos onde a mesma SQL pode devolver número diferente:

      CAMADA 1, as premissas. Os cinco `int_futebol_premissas_*` são `materialized: table` — uma
                re-medição os RECONSTRÓI. Era aqui que morava o ruído da #78 (`AVG` fundindo
                médias parciais de shards em ponto flutuante). Depois da #78 as duas premissas de
                odds saem de `SAFE_DIVIDE(SUM(CAST(1.0/odd AS NUMERIC)), COUNT(...))`: soma em
                ponto FIXO, que é exata e não depende da ordem. A camada 1 é determinística POR
                CONSTRUÇÃO, não por sorte de medição — e a #78 a mediu em 8 execuções
                (`linha_subindo`/`linha_descendo` cravadas em 1967/2579).

      CAMADA 2, a agregação do Teste 2 — esta análise. `AVG(IF(pl.acesa, ...))` sobre FLOAT64, o
                MESMO agregado instável que a #78 tirou dos modelos. A guarda
                `assert_premissas_sem_agregado_instavel` cobre MODELO, não análise, então ele
                continua aqui, e continua sendo o instrumento com que a [F] se mede. Ninguém
                tinha medido esta camada sozinha.

    A saída traz o valor BRUTO ao lado do arredondado de propósito. O `ROUND(·, 1)` do Teste 2
    esconde o tremor: duas execuções podem diferir no 15º dígito e imprimir o mesmo número — até
    a linha cair em cima da grade, e aí ela pula 0,1 de uma vez. O bruto diz o tamanho REAL do
    tremor; o arredondado diz se ele já chegou a atravessar a grade. Sem os dois lado a lado,
    "8 execuções idênticas" pode significar "não há tremor" ou "não houve empate nesta rodada",
    e essas duas coisas pedem decisões diferentes.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE ELA MEDE, E SOBRE QUE UNIVERSO

    Universo congelado da [F] (`macros/taskf_universo.sql`), os mesmos 169 jogos, porque é ele o
    universo da guarda que consome a régua (`assert_taskf_base_reproduz_01` compara
    `universo = 'completo'`). No congelado a coleta de odds já parou, então o insumo é imóvel e
    tudo que sobrar entre execuções é instrumento — que é exatamente o que se quer isolar.

    Os campos são os SEIS que a guarda cobra em pp, e só eles. Os `n_p*` vão junto como camada de
    contagem: se eles se mexerem, o problema não é arredondamento, é linha entrando e saindo.

    ⚠️ ELA NÃO MEDE A OUTRA COMPONENTE DA TOLERÂNCIA — o movimento LEGÍTIMO de odds no universo
    estendido, que a #78 não tocou. Ali a coleta ainda alcança o presente e uma janela t15m nova
    muda quais linhas acendem. Nenhum consumidor da var compara esse universo hoje (a guarda e a
    `analyses/taskf_reconciliacao_01.sql` são as duas, e as duas leem `completo`), mas quem
    escrever a primeira comparação sobre o `estendido` precisa medir essa componente ANTES de
    reusar o número desta análise.

    ⚠️ SEM `--target taskF`, E ISSO É DELIBERADO — é a única análise `taskf_*` que roda no target
    default, então vale a linha. As outras leem as CÉLULAS materializadas em `futebol_taskF`; esta
    não lê célula nenhuma, ela reexecuta o instrumento. E o que ela precisa reexecutar é o código
    de HOJE sobre os fatos de HOJE: em `futebol_taskF` as tabelas de premissas guardam a última
    célula que a receita construiu, sob o código PRÉ-#78 — medir o ruído pós-#78 ali seria medir o
    ruído que a #78 já tirou. O dataset `futebol` é também, por definição, a configuração da célula
    `base` (os defaults de produção), que é a célula da guarda.

    Nada é materializado: `dbt compile` + `bq query` sobre um SELECT não escreve, então a ADR 0007
    continua respeitada na letra e no espírito — o que ela proíbe é PUBLICAR medição no board.

    Rodar N vezes seguidas e comparar as saídas — sem `dbt run`, sem escrever em dataset nenhum:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskf_ruido_do_instrumento
      for i in $(seq 1 8); do
        bq query --use_legacy_sql=false --project_id=smartbetting-dados --format=csv \
          < target/compiled/dbt_futebol/analyses/taskf_ruido_do_instrumento.sql > /tmp/run_$i.csv
      done
      for i in $(seq 2 8); do diff -q /tmp/run_1.csv /tmp/run_$i.csv; done

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`, seção do ticket #92.
#}

{#- OS PISOS SÃO OS DA GUARDA, E NÃO OS DE `macros/taskf_pisos()` — a diferença é de propósito e
    tem de estar escrita, porque o macro diz que a lista "precisa existir num lugar só".

    `taskf_pisos()` é `[0, 3, 5, 10]`: a varredura de piso da MEDIÇÃO, que a spec #49 pediu para
    distinguir achado de escolha de corte. Aqui a lista é outra coisa — são os pisos que aparecem
    nos seis campos `em_pp: true` da `tests/assert_taskf_base_reproduz_01.sql`, isto é, os campos
    que a RÉGUA governa. Nenhum campo em pp da guarda está no piso 3, então medir p3 seria medir
    ruído de um campo que a régua não cobre.

    ⚠️ As duas listas são independentes e podem derivar: se a guarda passar a cobrar um campo em
    pp num piso novo, ELE PRECISA ENTRAR AQUI À MÃO. O acoplamento é com o `campos` da guarda, não
    com `taskf_pisos()` — e é por isso que herdar do macro seria o erro, não a correção. -#}
{%- set pisos_da_guarda = [0, 5, 10] -%}

WITH {{ task01_base() }},

{#- A agregação do Teste 2, recortada no universo congelado. É uma cópia da
    `analyses/taskf_teste2.sql` pelo mesmo motivo que ela é cópia da `analyses/task01_teste2.sql`:
    o que se quer reproduzir aqui é o INSTRUMENTO, com o `AVG` e tudo, e não uma versão limpa
    dele. Extrair para macro compartilhado trocaria o instrumento medido por outro.

    Usa `a.min_jogos` (o USADO) e não a `min_jogos_disponivel` da #54, e a igualdade das duas na
    célula `base` é conferível LENDO, não uma alegação sobre o dado: sob recorte `temporada` o
    `taskf_teste2.sql` resolve `col_disponivel = 'played_total'`, e aí o `pit_disponivel` dele
    (linhas 269-280) fica sendo a MESMA expressão do `pit` do `macros/task01_base.sql` (linhas
    316-327) — mesma tabela, mesmos dois LEFT JOIN por time, mesmo
    `LEAST(COALESCE(h.played_total, 0), COALESCE(a.played_total, 0))`. Não são dois números que
    coincidem: é uma expressão escrita duas vezes.

    ⚠️ Isso vale porque a célula é a `base`. Sob `ultimos_10` o `played_total` satura no teto e as
    duas contagens divergem de verdade (é o achado da #54) — esta análise mediria outra coisa. -#}
agregado AS (
    SELECT
        a.market_id,
        pl.premissa,
        a.benchmark,
        AVG(IF(pl.acesa, IF(a.min_jogos < 5, 1.0, 0.0), NULL))   AS frac_curta
        {%- for piso in pisos_da_guarda %},
        COUNTIF(pl.acesa AND a.min_jogos >= {{ piso }})          AS n_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos >= {{ piso }},
               a.prob_justa_fechamento, NULL))                   AS p_odd_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos >= {{ piso }},
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_{{ piso }}
        {%- endfor %}
    FROM apostas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    WHERE {{ taskf_universo_filtro('a.') }}
    GROUP BY a.market_id, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
),

{#- O carimbo da construção dos fatos entra na SAÍDA para que "as 8 execuções leram o mesmo
    insumo" seja conferível na linha, e não acreditado. Se um rebuild agendado cair no meio da
    medição, este número muda e as 8 deixam de ser 8 execuções idênticas — sem ele, a diferença
    apareceria como tremor do instrumento, que é a leitura errada. -#}
fatos AS (
    SELECT MAX(dbt_loaded_at) AS odds_loaded_at
    FROM {{ ref('fact_odds_snapshot') }}
)

SELECT
    f.odds_loaded_at,
    CASE g.market_id
        {%- for mid, m in task01_markets().items() %}
        WHEN {{ mid }} THEN '{{ m.nome }}'
        {%- endfor %}
    END                                                          AS mercado,
    g.premissa,
    g.benchmark,
    -- A camada de contagem. Ela se mexer é outro fenômeno, e a saída tem de saber distinguir.
    {%- for piso in pisos_da_guarda %}
    g.n_{{ piso }}                                               AS n_p{{ piso }},
    {%- endfor %}
    -- Os seis campos em pp que a `assert_taskf_base_reproduz_01` cobra, cada um em duas versões:
    -- o arredondado que a guarda compara e o bruto que mostra o tremor antes de ele chegar à
    -- grade. `bruto` em 12 casas — o tremor do `AVG` vive na 15ª, então 12 é folga e não corta
    -- nada que importe.
    ROUND(g.frac_curta * 100, 1)                                 AS pct_amostra_curta,
    ROUND(g.frac_curta * 100, 12)                                AS pct_amostra_curta_bruto,
    ROUND(g.p_odd_0  * 100, 1)                                   AS a_odd_dava_p0,
    ROUND(g.p_odd_0  * 100, 12)                                  AS a_odd_dava_p0_bruto,
    ROUND(g.p_real_0 * 100, 1)                                   AS aconteceu_p0,
    ROUND(g.p_real_0 * 100, 12)                                  AS aconteceu_p0_bruto
    {%- for piso in pisos_da_guarda %},
    ROUND((g.p_real_{{ piso }} - g.p_odd_{{ piso }}) * 100, 1)   AS diferenca_p{{ piso }},
    ROUND((g.p_real_{{ piso }} - g.p_odd_{{ piso }}) * 100, 12)  AS diferenca_p{{ piso }}_bruto
    {%- endfor %}
FROM agregado AS g
CROSS JOIN fatos AS f
ORDER BY mercado, g.premissa, g.benchmark
