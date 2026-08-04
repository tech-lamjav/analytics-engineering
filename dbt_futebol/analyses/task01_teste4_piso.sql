{#
    Task [0.1] — TESTE 4 sob piso de amostra, coerente nas duas pontas, mais a variante
    de premissa forte.  Ticket #9, spec #3.

    ════════════════════════════════════════════════════════════════════════════════
    CORRIGE UMA INCOERÊNCIA DO #8: lá o piso de 5 foi aplicado aos PESOS, mas o ROI foi
    medido no universo inteiro. A decisão registrada era aplicar o MESMO filtro nas duas
    pontas — senão o artefato de amostra curta entra pelos pesos e sai filtrado na
    medição, com as duas metades descrevendo universos diferentes.

    Aqui cada corte é coerente: piso P gera os pesos com P e mede o ROI com P.
    ════════════════════════════════════════════════════════════════════════════════
    VARIANTE DE PREMISSA FORTE: guarda-corpo contra a nota somar por acúmulo de sinal
    fraco. Exige que ao menos UMA premissa acesa tenha ganho medido >= 5 pp no Teste 2
    daquele piso. Usa o ganho CRU e não o peso encolhido de propósito — "forte" é sobre
    o tamanho do efeito, não sobre quanto dele sobreviveu à amostra.

    COMPOSIÇÃO POR COMPETIÇÃO: o piso não é um botão de qualidade de amostra, é um
    filtro de competição disfarçado — mata-mata é estruturalmente de amostra curta. O
    bloco C mostra o que cada corte deixa de pé, para que a escolha do piso seja feita
    de olhos abertos.

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_teste4_piso
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_teste4_piso.sql
#}

{%- set pisos = [0, 5, 10] -%}

WITH {{ task01_base() }},

validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

linhas_prem AS (
    SELECT a.*, pl.premissa, pl.acesa
    FROM validas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
),

{#- Pesos por piso, medidos só no benchmark preferido de cada mercado. -#}
pesos AS (
    {%- for piso in pisos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        {{ piso }} AS piso, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        GREATEST((AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
                - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100, 0)
        * SAFE_DIVIDE(COUNTIF(acesa), COUNTIF(acesa) + 50)   AS peso
    FROM linhas_prem
    WHERE min_jogos >= {{ piso }}
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    {%- endfor %}
),
teto AS (SELECT piso, market_id, SUM(peso) AS pts_max FROM pesos GROUP BY piso, market_id),

{#- Nota por (aposta, piso). O universo de AVALIAÇÃO também respeita o piso. -#}
notas AS (
    SELECT
        l.fixture_id, l.market_id, p.piso,
        LEAST(GREATEST(SAFE_DIVIDE(SUM(IF(l.acesa, p.peso, 0)),
                                   ANY_VALUE(t.pts_max)) * 100, 0), 100) AS nota_pct,
        IF(ANY_VALUE(l.ganhou), ANY_VALUE(l.best_odd), 0) - 1            AS lucro,
        -- guarda-corpo: alguma premissa acesa com ganho medido >= 5 pp?
        LOGICAL_OR(l.acesa AND p.ganho >= 5)                             AS tem_forte
    FROM linhas_prem AS l
    JOIN pesos AS p
      ON p.market_id = l.market_id AND p.premissa = l.premissa
    JOIN teto AS t
      ON t.piso = p.piso AND t.market_id = l.market_id
    WHERE l.min_jogos >= p.piso
    GROUP BY l.fixture_id, l.market_id, l.outcome_side, l.line_value, p.piso
),

expandido AS (
    SELECT n.*, v.variante
    FROM notas AS n
    CROSS JOIN UNNEST([STRUCT('1. todas'              AS variante),
                       STRUCT('2. com premissa forte' AS variante)]) AS v
    WHERE v.variante = '1. todas' OR n.tem_forte
),

resumo AS (
    SELECT
        'A. resumo' AS bloco,
        CONCAT('piso ', LPAD(CAST(piso AS STRING), 2, '0')) AS corte,
        variante,
        COUNT(*)                                            AS n_apostas,
        COUNT(DISTINCT fixture_id)                          AS n_jogos,
        ROUND(AVG(lucro) * 100, 1)                          AS roi_geral,
        ROUND(COVAR_SAMP(lucro, nota_pct)
              / NULLIF(VAR_SAMP(nota_pct), 0) * 100, 3)     AS inclinacao,
        ROUND((AVG(IF(nota_pct >= 60, lucro, NULL))
             - AVG(IF(nota_pct <  20, lucro, NULL))) * 100, 1) AS gap_alta_baixa,
        CAST(NULL AS STRING)                                AS faixa,
        CAST(NULL AS FLOAT64)                               AS roi_faixa,
        CAST(NULL AS FLOAT64)                               AS jogos_medios
    FROM expandido
    GROUP BY piso, variante
),

faixas AS (
    SELECT
        'B. faixas' AS bloco,
        CONCAT('piso ', LPAD(CAST(piso AS STRING), 2, '0')) AS corte,
        variante,
        COUNT(*)                                            AS n_apostas,
        COUNT(DISTINCT fixture_id)                          AS n_jogos,
        CAST(NULL AS FLOAT64)                               AS roi_geral,
        CAST(NULL AS FLOAT64)                               AS inclinacao,
        CAST(NULL AS FLOAT64)                               AS gap_alta_baixa,
        CASE WHEN nota_pct >= 80 THEN 'e. 80-100'
             WHEN nota_pct >= 60 THEN 'd. 60-80'
             WHEN nota_pct >= 40 THEN 'c. 40-60'
             WHEN nota_pct >= 20 THEN 'b. 20-40'
             ELSE                     'a. 00-20' END        AS faixa,
        ROUND(AVG(lucro) * 100, 1)                          AS roi_faixa,
        CAST(NULL AS FLOAT64)                               AS jogos_medios
    FROM expandido
    GROUP BY piso, variante, faixa
),

{#- O que cada piso deixa de pé, por competição. -#}
composicao AS (
    SELECT
        'C. composicao' AS bloco,
        CONCAT('piso ', LPAD(CAST(p.piso AS STRING), 2, '0')) AS corte,
        v.competition                                       AS variante,
        COUNT(*)                                            AS n_apostas,
        COUNT(DISTINCT v.fixture_id)                        AS n_jogos,
        ROUND(AVG(v.lucro_) * 100, 1)                       AS roi_geral,
        CAST(NULL AS FLOAT64)                               AS inclinacao,
        CAST(NULL AS FLOAT64)                               AS gap_alta_baixa,
        CAST(NULL AS STRING)                                AS faixa,
        CAST(NULL AS FLOAT64)                               AS roi_faixa,
        ROUND(AVG(v.min_jogos), 1)                          AS jogos_medios
    FROM (SELECT *, IF(ganhou, best_odd, 0) - 1 AS lucro_ FROM validas) AS v
    CROSS JOIN (SELECT DISTINCT piso FROM pesos) AS p
    WHERE v.min_jogos >= p.piso
    GROUP BY p.piso, v.competition
)

SELECT * FROM resumo
UNION ALL SELECT * FROM faixas
UNION ALL SELECT * FROM composicao
ORDER BY bloco, corte, variante, faixa
