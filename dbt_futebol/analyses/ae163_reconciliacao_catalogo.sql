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

    Benchmark: números ad-hoc do Victor (doc de metodologia, seção de ganhos por premissa):
      domina_posse        +15,26pp  n=201
      cria_mais_chance    +14,84pp  n=196   (chamado "xg" no doc)
      forca_mais_escanteio +10,80pp n=201
      ataca_mais_area      +7,44pp  n=220
      forca_escanteio_mando(Home) +6,70pp n=255
      jogo_muito_escanteio +5,46pp n=244
      jogo_pouco_escanteio +16,79pp n=137
      forca_mais_escanteio(Away)  +11,08pp n=172
      forca_escanteio_mando(Away) +9,29pp  n=162
      decisao               +7,01pp n=78

    Rodar com:
      dbt compile --select ae163_reconciliacao_catalogo
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae163_reconciliacao_catalogo.sql
#}

WITH {{ ae161_base_escanteios(cutoff='2026-09-10', janela_fixa='t24h', gates_do_board=false, liquidez_min_casas=3) }},

premissas_por_lado AS (
    {%- set combos = [] -%}
    {%- for p in ae161_premissas_home() -%}
        {%- set _ = combos.append(('Home', p)) -%}
    {%- endfor -%}
    {%- for p in ae161_premissas_away(incluir_decisao=true) -%}
        {%- set _ = combos.append(('Away', p)) -%}
    {%- endfor -%}
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

agregado AS (
    SELECT
        pl.outcome_side AS lado,
        pl.premissa,
        COUNTIF(pl.acesa) AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL)) AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL)) AS p_real
    FROM premissas_por_lado pl
    JOIN apostas a
      ON  a.fixture_id   = pl.fixture_id
      AND a.outcome_side = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
      AND a.benchmark = 'pinnacle'
    GROUP BY lado, pl.premissa
    HAVING COUNTIF(pl.acesa) > 0
)

SELECT
    lado,
    premissa,
    n AS n_medido,
    ROUND((p_real - p_odd) * 100, 2) AS diferenca_pp_medida
FROM agregado
ORDER BY lado, diferenca_pp_medida DESC
