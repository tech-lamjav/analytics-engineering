{#
    AE#163 (spec #157) — reconciliação DESCRITIVA (sem porta pass/fail) do catálogo de 10
    premissas contra os ganhos publicados por Victor, rodada no MESMO universo que já
    reproduziu o ROI geral/por lado do #161 dentro de ±0,4pp (cutoff='2026-09-10',
    janela_fixa='t24h', gates_do_board=false, liquidez_min_casas=3).

    Objetivo (adendo ao pré-registro, comentário antes desta query): separar "o catálogo
    está mal implementado" de "o sinal não é estável" antes de fechar o veredito de
    sobrevivência do OOS (ae163_pesos_oos.sql). A porta de tolerância (±3pp) já foi
    consumida pela reprodução do #161 — aqui é comparação de sinal/ordem de grandeza, não
    um segundo pass/fail.

    DUAS BASES, lado a lado (achado do code-review pós-merge do #170 — a v1 deste arquivo
    só tinha a base 'linha' sem dizer isso explicitamente):
      - 'linha': uma linha por bookmaker/linha cotada — a MESMA base que o Victor usou
        ("domina a posse +15,26 em 201 LINHAS"; "sobre 1.464 LINHAS e 373 jogos", ClickUp
        wdx6zf1tt8 — ele não deduplicava por jogo/lado). É a base comparável aos números
        dele; deduplicar aqui trocaria a base de comparação sem avisar.
      - 'jogo_lado': uma linha por (fixture_id, outcome_side), a mais líquida — a MESMA
        regra do OOS (`apostas_unica` do ae163_pesos_oos.sql). Serve pra checar se a leitura
        muda quando linhas correlacionadas do mesmo jogo não pesam mais de uma vez.

    Blocos de saída, sem agregar ROI fora do que já era o objeto desta reconciliação:
      'ganho'     — diferença medida por (base, lado, premissa), as duas bases.
      'taxa'      — % de linhas/jogos-lado que acendem cada premissa (o catálogo do Victor
                    foi calibrado pra ~25%, percentil 75 da distribuição dele — se a taxa
                    medida aqui for bem menor, os cortes fixos não transferem pra esta
                    distribuição, que tem mais jogos europeus).
      'cobertura' — quantas linhas/jogos-lado (min_jogos>=10) têm um par 'pinnacle' no
                    mesmo (fixture,lado,line_value) — o benchmark usado para o peso (#161).
                    Sem isso, o INNER JOIN com benchmark='pinnacle' descarta linhas
                    consenso-only sem nenhum diagnóstico visível.

    Rodar com:
      dbt compile --select ae163_reconciliacao_catalogo
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae163_reconciliacao_catalogo.sql
#}

WITH {{ ae161_base_escanteios(cutoff='2026-09-10', janela_fixa='t24h', gates_do_board=false, liquidez_min_casas=3) }},

apostas_unica AS (
    SELECT *
    FROM apostas
    WHERE min_jogos >= 10
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, outcome_side
        ORDER BY n_casas DESC, ABS(line_value) ASC, line_value ASC
    ) = 1
),

{%- set combos = [] -%}
{%- for p in ae161_premissas_home() -%}
    {%- set _ = combos.append(('Home', p)) -%}
{%- endfor -%}
{%- for p in ae161_premissas_away(incluir_decisao=true) -%}
    {%- set _ = combos.append(('Away', p)) -%}
{%- endfor -%}

premissas_linha AS (
    {%- for lado, p in combos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        fixture_id, outcome_side, line_value,
        '{{ p.premissa }}' AS premissa,
        (COALESCE({{ p.sql }}, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = '{{ lado }}'
    {%- endfor %}
),

premissas_jogo AS (
    {%- for lado, p in combos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        fixture_id, outcome_side, line_value,
        '{{ p.premissa }}' AS premissa,
        COALESCE({{ p.sql }}, FALSE) AS acesa
    FROM apostas_unica
    WHERE outcome_side = '{{ lado }}'
    {%- endfor %}
),

agregado_linha AS (
    SELECT
        'linha' AS base,
        pl.outcome_side AS lado,
        pl.premissa,
        COUNTIF(pl.acesa) AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL)) AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL)) AS p_real
    FROM premissas_linha pl
    JOIN apostas a
      ON  a.fixture_id   = pl.fixture_id
      AND a.outcome_side = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
    WHERE a.benchmark = 'pinnacle'
    GROUP BY pl.outcome_side, pl.premissa
    HAVING COUNTIF(pl.acesa) > 0
),

agregado_jogo AS (
    SELECT
        'jogo_lado' AS base,
        pl.outcome_side AS lado,
        pl.premissa,
        COUNTIF(pl.acesa) AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL)) AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL)) AS p_real
    FROM premissas_jogo pl
    JOIN apostas_unica a
      ON  a.fixture_id   = pl.fixture_id
      AND a.outcome_side = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
    WHERE a.benchmark = 'pinnacle'
    GROUP BY pl.outcome_side, pl.premissa
    HAVING COUNTIF(pl.acesa) > 0
),

universo_lado AS (
    SELECT 'linha' AS base, outcome_side AS lado, COUNT(*) AS total
    FROM apostas WHERE min_jogos >= 10
    GROUP BY 1, 2

    UNION ALL

    SELECT 'jogo_lado' AS base, outcome_side AS lado, COUNT(*) AS total
    FROM apostas_unica
    GROUP BY 1, 2
),

taxa_acender AS (
    SELECT 'linha' AS base, outcome_side AS lado, premissa, COUNTIF(acesa) AS n_acesas
    FROM premissas_linha GROUP BY 1, 2, 3

    UNION ALL

    SELECT 'jogo_lado' AS base, outcome_side AS lado, premissa, COUNTIF(acesa) AS n_acesas
    FROM premissas_jogo GROUP BY 1, 2, 3
),

cobertura_pinnacle AS (
    SELECT 'linha' AS base, COUNT(*) AS total, COUNTIF(benchmark = 'pinnacle') AS com_pinnacle
    FROM apostas WHERE min_jogos >= 10

    UNION ALL

    SELECT 'jogo_lado' AS base, COUNT(*) AS total, COUNTIF(benchmark = 'pinnacle') AS com_pinnacle
    FROM apostas_unica
)

SELECT
    'ganho' AS bloco, base, lado, premissa,
    n AS n_ou_total,
    ROUND((p_real - p_odd) * 100, 2) AS valor,
    CAST(NULL AS INT64) AS extra
FROM (
    SELECT * FROM agregado_linha
    UNION ALL
    SELECT * FROM agregado_jogo
)

UNION ALL

SELECT
    'taxa' AS bloco, t.base, t.lado, t.premissa,
    t.n_acesas AS n_ou_total,
    ROUND(100.0 * SAFE_DIVIDE(t.n_acesas, u.total), 1) AS valor,
    u.total AS extra
FROM taxa_acender t
JOIN universo_lado u USING (base, lado)

UNION ALL

SELECT
    'cobertura' AS bloco, base, CAST(NULL AS STRING) AS lado, CAST(NULL AS STRING) AS premissa,
    total AS n_ou_total,
    ROUND(100.0 * SAFE_DIVIDE(com_pinnacle, total), 1) AS valor,
    com_pinnacle AS extra
FROM cobertura_pinnacle

ORDER BY bloco, base, lado, valor DESC
