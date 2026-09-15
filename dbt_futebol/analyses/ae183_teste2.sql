{#
    AE#183 (spec #179) — TESTE 2 do Total de escanteios (market_id 45), catálogo COMPLETO
    (18 premissas × 2 lados = 36 combinações, ver comentário de
    ae183_premissas_escanteios_total.sql pra por que "completo" e não só o subconjunto de
    9-por-lado que o documento original lista como sobrevivente).

    Colunas de sempre (mercado, lado, premissa, n, benchmark, o que a odd dava, o que
    aconteceu, a diferença) — mesmo formato do task01_teste2.sql / ae161_teste2.sql.

    Universo: janela VIVA (sem corte de data), gates do board (liquidez>=4, not outlier,
    odd 1,50-4,00), janela de odds CORRENTE, linha principal (odd mais perto de 2,00 ENTRE
    as que sobrevivem aos gates) — tudo declarado no pré-registro da issue #183 antes desta
    query rodar.

    Rodar com:
      dbt compile --select ae183_teste2
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae183_teste2.sql
#}

WITH {{ ae183_base_escanteios_total(cutoff=none, janela_fixa=none, gates_do_board=true) }},

premissas AS (
    {{ ae183_premissas_escanteios_total_sql(tabela='apostas') }}
),

janela AS (
    SELECT
        MIN(DATE(kickoff_utc)) AS janela_ini,
        MAX(DATE(kickoff_utc)) AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*) AS linhas_no_universo
    FROM apostas
),

agregado AS (
    SELECT
        pr.lado,
        pr.premissa,
        pr.benchmark,
        COUNTIF(pr.acesa)                                      AS n,
        AVG(IF(pr.acesa, pr.prob_justa_fechamento, NULL))      AS p_odd,
        AVG(IF(pr.acesa, CAST(pr.ganhou AS INT64), NULL))      AS p_real
    FROM premissas pr
    GROUP BY lado, pr.premissa, pr.benchmark
    HAVING COUNTIF(pr.acesa) > 0
)

SELECT
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    j.linhas_no_universo,
    'Total de escanteios' AS mercado,
    g.lado,
    g.premissa,
    g.benchmark,
    -- só o benchmark PREFERIDO (pinnacle) entra em qualquer leitura de "sobrevive/zera" —
    -- consenso é 7 de 1.261 linhas no universo do Teste 2 (ver pré-registro), fica marcado
    -- mas não pesa, mesma regra do #161.
    (g.benchmark = 'pinnacle')                                  AS usado_para_leitura,
    g.n,
    ROUND(g.p_odd  * 100, 1)                                    AS a_odd_dava_pct,
    ROUND(g.p_real * 100, 1)                                    AS aconteceu_pct,
    ROUND((g.p_real - g.p_odd) * 100, 1)                        AS diferenca_pp,
    IF((g.p_real - g.p_odd) <= 0, 'ZERADA — sem ganho', 'com ganho') AS veredito
FROM agregado g
CROSS JOIN janela j
ORDER BY g.lado, g.benchmark DESC, diferenca_pp DESC
