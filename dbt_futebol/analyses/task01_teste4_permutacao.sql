{#
    Task [0.1] — TESTE 4, curva NULA por permutação.  Ticket #8, spec #3.

    O `task01_teste4.sql` mediu a inclinação do ROI contra a nota: +0,238 pp por ponto
    de nota com pesos do Teste 2, e +0,223 out-of-sample. A pergunta que falta é a única
    que dá significado a esses números: **qual inclinação o ACASO produz nesta amostra?**

    Com 169 jogos e apostas correlacionadas dentro de cada jogo, uma inclinação positiva
    pode ser inteiramente ruído. Sem a distribuição nula, +0,223 é um número sem régua.

    ────────────────────────────────────────────────────────────────────────────────
    MÉTODO: 200 réplicas. Em cada uma, os pesos são EMBARALHADOS entre as premissas do
    MESMO mercado — a distribuição de pesos fica idêntica, muda só quem recebe qual.

    Isso isola exatamente a hipótese em teste. Se a nota ordena porque as premissas
    certas têm os pesos certos, embaralhar destrói o sinal. Se ela ordena por qualquer
    razão estrutural (mercados com pesos maiores serem melhores, faixas altas terem
    odds diferentes), o embaralhamento preserva — e a inclinação observada não prova
    nada sobre as premissas.

    AUTOTESTE: se a mediana das réplicas embaralhadas vier claramente positiva, o
    defeito está na normalização ou no binning, não no mundo — e o Teste 4 inteiro não
    está pronto. É critério de aceite do ticket #8.
    ────────────────────────────────────────────────────────────────────────────────

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_teste4_permutacao
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_teste4_permutacao.sql
#}

{%- set n_reps = 200 -%}

WITH {{ task01_base() }},

validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

para_peso AS (
    SELECT a.market_id, a.ganhou, a.prob_justa_fechamento, pl.premissa, pl.acesa
    FROM validas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    WHERE a.benchmark = CASE a.market_id
                            WHEN 12 THEN 'derivada'
                            WHEN 8  THEN 'consenso'
                            ELSE         'sharp'
                        END
      AND a.min_jogos >= 5
),

{#- Pesos reais do Teste 2, piso 5 — os mesmos do `task01_teste4.sql`. -#}
pesos AS (
    SELECT market_id, premissa,
           GREATEST((AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
                   - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(acesa), COUNTIF(acesa) + 50) AS peso
    FROM para_peso
    GROUP BY market_id, premissa
),

{#- Réplica 0 = a atribuição VERDADEIRA; 1..N = embaralhadas. Manter a real dentro da
    mesma máquina garante que ela e o nulo passem pelo mesmo caminho de código. -#}
reps AS (
    SELECT rep FROM UNNEST(GENERATE_ARRAY(0, {{ n_reps }})) AS rep
),

{#- Duas ordenações do mesmo conjunto de pesos por mercado: a premissa recebe o peso que
    caiu na sua posição sorteada. Na réplica 0 as duas ordens coincidem. -#}
ordenado AS (
    SELECT
        p.market_id, p.premissa, p.peso,
        r.rep,
        ROW_NUMBER() OVER (PARTITION BY p.market_id, r.rep ORDER BY p.premissa) AS pos_real,
        ROW_NUMBER() OVER (PARTITION BY p.market_id, r.rep
                           ORDER BY IF(r.rep = 0,
                                       CAST(FARM_FINGERPRINT(p.premissa) AS FLOAT64),
                                       CAST(FARM_FINGERPRINT(CONCAT(p.premissa, '#',
                                            CAST(r.rep AS STRING))) AS FLOAT64))) AS pos_sorteada
    FROM pesos AS p
    CROSS JOIN reps AS r
),
pesos_rep AS (
    SELECT
        a.market_id, a.rep, a.premissa,
        IF(a.rep = 0, a.peso, b.peso) AS peso
    FROM ordenado AS a
    JOIN ordenado AS b
      ON b.market_id = a.market_id AND b.rep = a.rep AND b.pos_real = a.pos_sorteada
),
teto AS (
    SELECT market_id, rep, SUM(peso) AS pts_max FROM pesos_rep GROUP BY market_id, rep
),

notas AS (
    SELECT
        a.fixture_id, pr.rep,
        LEAST(GREATEST(SAFE_DIVIDE(SUM(IF(pl.acesa, pr.peso, 0)),
                                   ANY_VALUE(t.pts_max)) * 100, 0), 100) AS nota_pct,
        IF(ANY_VALUE(a.ganhou), ANY_VALUE(a.best_odd), 0) - 1            AS lucro
    FROM validas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    JOIN pesos_rep AS pr
      ON pr.market_id = pl.market_id AND pr.premissa = pl.premissa
    JOIN teto AS t
      ON t.market_id = a.market_id AND t.rep = pr.rep
    GROUP BY a.fixture_id, a.market_id, a.outcome_side, a.line_value, pr.rep
),

inclinacoes AS (
    SELECT
        rep,
        COVAR_SAMP(lucro, nota_pct) / NULLIF(VAR_SAMP(nota_pct), 0) * 100 AS inclinacao,
        -- Separação entre a faixa alta e a baixa, em pp de ROI. É a leitura de produto:
        -- "apostar só nas notas altas rende quanto a mais que apostar só nas baixas?"
        (AVG(IF(nota_pct >= 60, lucro, NULL)) - AVG(IF(nota_pct < 20, lucro, NULL))) * 100
                                                                          AS gap_alta_baixa
    FROM notas
    GROUP BY rep
),

observado AS (SELECT inclinacao, gap_alta_baixa FROM inclinacoes WHERE rep = 0),
nulo      AS (SELECT * FROM inclinacoes WHERE rep > 0)

SELECT
    'inclinacao (pp de ROI por ponto de nota)'                    AS metrica,
    ROUND(ANY_VALUE(o.inclinacao), 3)                             AS observado,
    ROUND(APPROX_QUANTILES(n.inclinacao, 100)[OFFSET(50)], 3)     AS nulo_mediana,
    ROUND(APPROX_QUANTILES(n.inclinacao, 100)[OFFSET(5)],  3)     AS nulo_p05,
    ROUND(APPROX_QUANTILES(n.inclinacao, 100)[OFFSET(95)], 3)     AS nulo_p95,
    ROUND(MAX(n.inclinacao), 3)                                   AS nulo_max,
    -- p-valor unicaudal: fração das réplicas embaralhadas que igualam ou superam o
    -- observado. É a régua que faltava.
    ROUND(SAFE_DIVIDE(COUNTIF(n.inclinacao >= o.inclinacao), COUNT(*)), 3) AS p_valor
FROM nulo AS n CROSS JOIN observado AS o

UNION ALL

SELECT
    'gap faixa alta (>=60) menos faixa baixa (<20), em pp',
    ROUND(ANY_VALUE(o.gap_alta_baixa), 1),
    ROUND(APPROX_QUANTILES(n.gap_alta_baixa, 100)[OFFSET(50)], 1),
    ROUND(APPROX_QUANTILES(n.gap_alta_baixa, 100)[OFFSET(5)],  1),
    ROUND(APPROX_QUANTILES(n.gap_alta_baixa, 100)[OFFSET(95)], 1),
    ROUND(MAX(n.gap_alta_baixa), 1),
    ROUND(SAFE_DIVIDE(COUNTIF(n.gap_alta_baixa >= o.gap_alta_baixa), COUNT(*)), 3)
FROM nulo AS n CROSS JOIN observado AS o
