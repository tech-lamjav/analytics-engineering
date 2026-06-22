{{ config(
    materialized='view',
    description='Fase 0 do Motor de Score — núcleo de VALOR (agnóstico de mercado). 1 linha por (fixture_id, market_id, outcome_side, line_value). Calcula, na janela de FECHAMENTO mais recente disponível (t15m>t1h>t24h): best_odd/avg_odd/n_casas entre TODAS as casas, o de-vig market-aware da Pinnacle (bookmaker_id=4) sobre o conjunto de outcomes do mercado, o edge e o PTS_VALOR (0-30), as 4 penalidades globais e o sinal linha_sharp (movimento Pinnacle t24h->t15m). NÃO aplica o gate (isso é no mart). ⚠️ De-vig correto p/ mercados exaustivos por (market,line): 1X2(3)/O/U(2)/BTTS(2); Asian Handicap(4) e Double Chance(12) exigem pareamento próprio (S3/S5) — não consumir prob_justa desses até lá.'
) }}

WITH odds AS (
    SELECT
        fixture_id,
        competition,
        season,
        market_id,
        outcome_side,
        line_value,
        -- chave NULL-safe da linha (1X2/BTTS têm line_value NULL -> 'NONE')
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key,
        bookmaker_id,
        bookmaker_name,
        collection_window,
        odd_decimal,
        CASE collection_window
            WHEN 't15m' THEN 3   -- fechamento (preferido)
            WHEN 't1h'  THEN 2
            WHEN 't24h' THEN 1
            ELSE 0
        END AS window_priority
    FROM {{ ref('fact_odds_snapshot') }}
    -- descarta Exact Score (10) e labels sem lado pareável
    WHERE outcome_side IS NOT NULL
),

-- Janela de avaliação por (fixture, market, linha): a mais recente disponível.
-- Tudo abaixo (best_odd, n_casas, devig) é calculado NESSA mesma janela.
eval_odds AS (
    SELECT *
    FROM odds
    QUALIFY window_priority = MAX(window_priority) OVER (
        PARTITION BY fixture_id, market_id, line_key
    )
),

-- Agregados por outcome (todas as casas na janela de avaliação).
per_outcome AS (
    SELECT
        fixture_id,
        ANY_VALUE(competition)        AS competition,
        ANY_VALUE(season)             AS season,
        market_id,
        outcome_side,
        line_value,
        line_key,
        ANY_VALUE(collection_window)  AS janela_usada,
        MAX(odd_decimal)              AS best_odd,
        AVG(odd_decimal)              AS avg_odd,
        COUNT(DISTINCT bookmaker_id)  AS n_casas,
        ARRAY_AGG(bookmaker_name ORDER BY odd_decimal DESC LIMIT 1)[OFFSET(0)] AS best_book
    FROM eval_odds
    GROUP BY fixture_id, market_id, outcome_side, line_value, line_key
),

-- De-vig market-aware da Pinnacle: prob_justa = (1/odd) / Σ(1/odd) sobre todos os
-- outcomes do (fixture, market, linha) na janela de avaliação (normalização multiplicativa).
pinnacle_eval AS (
    SELECT fixture_id, market_id, outcome_side, line_key, odd_decimal AS pin_odd
    FROM eval_odds
    WHERE bookmaker_id = 4
),
pinnacle_devig AS (
    SELECT
        fixture_id, market_id, outcome_side, line_key,
        (1.0 / pin_odd) / SUM(1.0 / pin_odd) OVER (
            PARTITION BY fixture_id, market_id, line_key
        )                                                         AS prob_justa_fechamento,
        SUM(1.0 / pin_odd)  OVER (PARTITION BY fixture_id, market_id, line_key) AS overround,
        COUNT(*)            OVER (PARTITION BY fixture_id, market_id, line_key) AS pin_n_outcomes
    FROM pinnacle_eval
),

-- Movimento de linha sharp: odd Pinnacle do lado caiu t24h -> t15m (mercado migrou pro
-- nosso lado). Precisa Pinnacle nas DUAS janelas; senão FALSE (graceful).
pinnacle_move AS (
    SELECT
        fixture_id, market_id, outcome_side, line_key,
        MAX(IF(collection_window = 't24h', odd_decimal, NULL)) AS pin_t24h,
        MAX(IF(collection_window = 't15m', odd_decimal, NULL)) AS pin_t15m
    FROM odds
    WHERE bookmaker_id = 4
    GROUP BY fixture_id, market_id, outcome_side, line_key
)

SELECT
    po.fixture_id,
    po.competition,
    po.season,
    po.market_id,
    po.outcome_side,
    po.line_value,
    po.janela_usada,
    po.best_odd,
    po.best_book,
    po.avg_odd,
    po.n_casas,
    pd.prob_justa_fechamento,
    pd.overround,
    pd.pin_n_outcomes,

    -- edge e PTS_VALOR (0-30). NULL quando não há de-vig (Pinnacle ausente/incompleto).
    (po.best_odd * pd.prob_justa_fechamento) - 1.0 AS edge,
    CAST(ROUND(
        LEAST(GREATEST((po.best_odd * pd.prob_justa_fechamento) - 1.0, 0) * 100, 6) / 6 * 30
    ) AS INT64) AS pts_valor,

    -- Penalidades globais (flags + total de pontos a subtrair).
    COALESCE(po.best_odd >= 1.10 * po.avg_odd, FALSE) AS pen_odd_outlier,
    COALESCE(po.n_casas < 4, FALSE)                   AS pen_poucas_casas,
    COALESCE(po.best_odd > 4.5, FALSE)                AS pen_odd_longshot,
    COALESCE(po.best_odd < 1.40, FALSE)               AS pen_odd_juice,
    (
        30 * CAST(COALESCE(po.best_odd >= 1.10 * po.avg_odd, FALSE) AS INT64)
      + 12 * CAST(COALESCE(po.n_casas < 4, FALSE) AS INT64)
      + 15 * CAST(COALESCE(po.best_odd > 4.5, FALSE) AS INT64)
      + 10 * CAST(COALESCE(po.best_odd < 1.40, FALSE) AS INT64)
    ) AS penalidades_globais_pts,

    -- Insumo de corroboração (consumido por int_futebol_corroboracao).
    COALESCE(pm.pin_t15m < pm.pin_t24h, FALSE) AS linha_sharp_confirma,

    CURRENT_TIMESTAMP() AS dbt_loaded_at

FROM per_outcome po
LEFT JOIN pinnacle_devig pd
    ON  po.fixture_id   = pd.fixture_id
    AND po.market_id    = pd.market_id
    AND po.outcome_side = pd.outcome_side
    AND po.line_key     = pd.line_key
LEFT JOIN pinnacle_move pm
    ON  po.fixture_id   = pm.fixture_id
    AND po.market_id    = pm.market_id
    AND po.outcome_side = pm.outcome_side
    AND po.line_key     = pm.line_key
