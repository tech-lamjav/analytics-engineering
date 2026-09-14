{#
    AE#161 (spec #157) — TESTE 2 do handicap de escanteios (market_id 56), premissa a
    premissa, por lado, no catálogo completo do ClickUp wdx6zf1tt8 MENOS "Decisão" (AE#162).

    Colunas da [0.1] (task01_teste2.sql): mercado, premissa, lado, n, benchmark, o que a odd
    dava, o que aconteceu, a diferença — mais o peso (ADR 0001, max(diferença,0) × n/(n+50)).

    Universo: janela VIVA (sem corte de data, convenção do task01_teste2.sql original — a
    janela exata sai em janela_ini/janela_fim), gates do board (liquidez>=4, not outlier,
    odd 1,50-4,00), janela de odds CORRENTE — declarado no pré-registro da issue #161 antes
    desta query rodar.

    Rodar com:
      dbt compile --select ae161_teste2
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae161_teste2.sql
#}

WITH {{ ae161_base_escanteios(cutoff=none, janela_fixa=none, gates_do_board=true) }},

premissas_por_lado AS (
    {%- set combos = [] -%}
    {%- for p in ae161_premissas_home() -%}
        {%- set _ = combos.append(('Home', p)) -%}
    {%- endfor -%}
    {%- for p in ae161_premissas_away() -%}
        {%- set _ = combos.append(('Away', p)) -%}
    {%- endfor -%}
    {%- for lado, p in combos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        fixture_id, outcome_side, line_value,
        '{{ p.premissa }}'      AS premissa,
        {{ p.peso }}            AS peso_original,
        COALESCE({{ p.sql }}, FALSE) AS acesa
    FROM apostas
    WHERE outcome_side = '{{ lado }}'
    {%- endfor %}
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
        pl.outcome_side                                         AS lado,
        pl.premissa,
        a.benchmark,
        COUNTIF(pl.acesa)                                       AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL))        AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL))        AS p_real,
        AVG(IF(pl.acesa, a.min_jogos, NULL))                    AS jogos_medios
    FROM premissas_por_lado pl
    JOIN apostas a
      ON  a.fixture_id    = pl.fixture_id
      AND a.outcome_side  = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
    GROUP BY lado, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
)

SELECT
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    j.linhas_no_universo,
    'Handicap de escanteios' AS mercado,
    g.lado,
    g.premissa,
    g.benchmark,
    -- só o benchmark PREFERIDO (sharp/pinnacle — mesma regra do [0.1]: consenso vai junto,
    -- marcado, mas não pesa) entra no peso.
    (g.benchmark = 'pinnacle')                                  AS usado_para_peso,
    g.n,
    ROUND(SAFE_DIVIDE(g.n, g.n + 50), 2)                        AS fator_encolhimento,
    ROUND(g.jogos_medios, 1)                                    AS jogos_medios,
    ROUND(g.p_odd  * 100, 1)                                    AS a_odd_dava_pct,
    ROUND(g.p_real * 100, 1)                                    AS aconteceu_pct,
    ROUND((g.p_real - g.p_odd) * 100, 1)                        AS diferenca_pp,
    -- peso = max(diferença, 0) × n/(n+50), ADR 0001. Ganho negativo -> peso ZERO (registrado
    -- explicitamente como "medida e zerada", não removido do catálogo).
    IF(g.benchmark = 'pinnacle',
       ROUND(GREATEST((g.p_real - g.p_odd) * 100, 0) * SAFE_DIVIDE(g.n, g.n + 50), 2),
       NULL)                                                    AS peso_medido,
    IF((g.p_real - g.p_odd) <= 0, 'ZERADA — sem ganho' , 'com ganho') AS veredito
FROM agregado g
CROSS JOIN janela j
ORDER BY g.lado, g.benchmark DESC, diferenca_pp DESC
