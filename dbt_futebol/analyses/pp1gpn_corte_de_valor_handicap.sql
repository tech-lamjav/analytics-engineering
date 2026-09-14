{#
    prop-play-predictor `wdx6zf1gpn` — Religar o handicap com corte de valor na vitrine.

    A medição original do ticket usou o board publicado (374 linhas) sem piso de
    histórico e sem os gates de preço do board. `task01_base()` já resolve os dois:
    `apostas` desde 2026-09-10 aplica as três portas de preço do board (liquidez
    estrita, outlier, faixa de odd — ver macro) e traz `min_jogos` (piso de amostra,
    ADR 0010). O "gate de completude" que o ticket citava como faltante NÃO existe no
    board hoje (confirmado no próprio `task01_base.sql`, 09/09) — não é reintroduzido
    aqui.

    Universo: market_id = 4 (Handicap), meia-linha já filtrada pelo macro. Corte
    testado: edge > -0.02 (o valor proposto no ticket) vs edge <= -0.02. Piso de
    histórico: min_jogos >= 5 (o piso [0.1]/ADR 0010 usa).

    Rodar com:
      dbt compile --select pp1gpn_corte_de_valor_handicap
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/pp1gpn_corte_de_valor_handicap.sql
#}

WITH {{ task01_base() }},

handicap AS (
    SELECT *
    FROM apostas
    WHERE market_id = 4
),

base_sem_piso AS (
    SELECT
        CASE WHEN edge > -0.02 THEN 'a. edge > -2% (fica)' ELSE 'b. edge <= -2% (corta)' END AS corte,
        'sem piso de historico' AS piso,
        COUNT(*) AS n_linhas,
        ROUND(100.0 * SUM(best_odd * CAST(ganhou AS INT64) - 1) / COUNT(*), 1) AS roi_pct,
        ROUND(100.0 * STDDEV(best_odd * CAST(ganhou AS INT64) - 1) / SQRT(COUNT(*)), 1) AS ep_pct
    FROM handicap
    GROUP BY 1
),

base_com_piso AS (
    SELECT
        CASE WHEN edge > -0.02 THEN 'a. edge > -2% (fica)' ELSE 'b. edge <= -2% (corta)' END AS corte,
        'com piso 5 (min_jogos >= 5)' AS piso,
        COUNT(*) AS n_linhas,
        ROUND(100.0 * SUM(best_odd * CAST(ganhou AS INT64) - 1) / COUNT(*), 1) AS roi_pct,
        ROUND(100.0 * STDDEV(best_odd * CAST(ganhou AS INT64) - 1) / SQRT(COUNT(*)), 1) AS ep_pct
    FROM handicap
    WHERE min_jogos >= 5
    GROUP BY 1
),

sem_corte AS (
    SELECT
        'z. sem corte (universo inteiro, referencia)' AS corte,
        piso,
        COUNT(*) AS n_linhas,
        ROUND(100.0 * SUM(best_odd * CAST(ganhou AS INT64) - 1) / COUNT(*), 1) AS roi_pct,
        ROUND(100.0 * STDDEV(best_odd * CAST(ganhou AS INT64) - 1) / SQRT(COUNT(*)), 1) AS ep_pct
    FROM handicap, UNNEST(['sem piso de historico', 'com piso 5 (min_jogos >= 5)']) AS piso
    WHERE piso = 'sem piso de historico' OR min_jogos >= 5
    GROUP BY 1, 2
),

janela_recente AS (
    -- Só desde a virada (#109, 2026-09-01), quando as tres portas de preco do board
    -- entraram em vigor de verdade em producao (antes disso elas nao valiam nada:
    -- o board publicava sob liquidez>=3, sem outlier/faixa). E so com piso 5. Testa
    -- se o resultado do universo inteiro nao esta sendo distorcido por historico de
    -- antes do modelo atual.
    SELECT
        CASE WHEN edge > -0.02 THEN 'a. edge > -2% (fica)' ELSE 'b. edge <= -2% (corta)' END AS corte,
        'so kickoff >= 2026-09-01, com piso 5' AS piso,
        COUNT(*) AS n_linhas,
        ROUND(100.0 * SUM(best_odd * CAST(ganhou AS INT64) - 1) / COUNT(*), 1) AS roi_pct,
        ROUND(100.0 * STDDEV(best_odd * CAST(ganhou AS INT64) - 1) / SQRT(COUNT(*)), 1) AS ep_pct
    FROM handicap
    WHERE min_jogos >= 5 AND DATE(kickoff_utc) >= DATE('2026-09-01')
    GROUP BY 1
),

conjunto_incompleto_check AS (
    SELECT
        conjunto_incompleto,
        COUNT(*) AS n_linhas
    FROM handicap
    GROUP BY 1
)

SELECT corte, piso, n_linhas, roi_pct, ep_pct FROM base_sem_piso
UNION ALL
SELECT corte, piso, n_linhas, roi_pct, ep_pct FROM base_com_piso
UNION ALL
SELECT corte, piso, n_linhas, roi_pct, ep_pct FROM sem_corte
UNION ALL
SELECT corte, piso, n_linhas, roi_pct, ep_pct FROM janela_recente
UNION ALL
SELECT CAST(conjunto_incompleto AS STRING), 'diagnostico conjunto_incompleto', n_linhas, NULL, NULL FROM conjunto_incompleto_check
ORDER BY piso, corte
