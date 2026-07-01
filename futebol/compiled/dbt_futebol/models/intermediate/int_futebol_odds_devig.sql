

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
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
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
        -- média DEIXANDO DE FORA a própria best_odd (leave-one-out): referência honesta p/ a
        -- penalidade pen_odd_outlier — senão a best_odd entra na própria média e mascara o
        -- outlier (soft/stale line). NULL quando só há 1 casa (sem comparação) -> penalidade FALSE.
        SAFE_DIVIDE(SUM(odd_decimal) - MAX(odd_decimal), COUNT(*) - 1) AS avg_odd_ex_best,
        APPROX_QUANTILES(odd_decimal, 2)[OFFSET(1)] AS med_odd,
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
      -- EXCLUI a Dupla Chance(12) — espelha o consensus_devig: suas 3 saídas NÃO são exaustivas
      -- (somam ~2), normalizar p/ 1 daria prob ~metade da real. A DC é DERIVADA do de-vig 1X2 da
      -- Pinnacle (dc_devig); este guard garante que o COALESCE final caia em dd.dc_prob_justa
      -- mesmo se a Pinnacle um dia passar a precificar o market 12 (hoje 0 fixtures).
      AND market_id <> 12
    -- 1 odd por (fixture, market, lado, linha) ANTES do de-vig: blinda o Σ(1/odd) de dupla
    -- contagem/fan-out caso dois labels distintos colapsem na mesma (lado, linha) ao parsear
    -- (ex.: '-1.5' vs '-1.50'). Mantém a melhor odd do lado (não muda nada hoje: 1 linha/lado).
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, market_id, outcome_side, line_key
        ORDER BY odd_decimal DESC
    ) = 1
),
pinnacle_devig AS (
    SELECT
        fixture_id, market_id, outcome_side, line_key,
        (1.0 / pin_odd) / SUM(1.0 / pin_odd) OVER (
            PARTITION BY fixture_id, market_id, line_key
        )                                                         AS prob_justa_fechamento,
        -- booksum = Σ(1/odd) = normalizador = 1 + margem (NÃO é a margem; margem = booksum − 1).
        SUM(1.0 / pin_odd)  OVER (PARTITION BY fixture_id, market_id, line_key) AS booksum_fechamento,
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
),

-- De-vig de CONSENSO: mesma normalização multiplicativa, mas sobre a MEDIANA das casas
-- (med_odd) por outcome em vez da Pinnacle. Fallback p/ mercados que a Pinnacle estruturalmente
-- não precifica (BTTS=8, HT/FT=7). Só é consumido quando a Pinnacle falta (o COALESCE no SELECT
-- preserva 1X2/O/U/AH byte-a-byte) e carrega a margem/viés das casas -> "edge vs consenso" é
-- sinal mais fraco que vs Pinnacle (rotular como "estimativa" no front via valor_fonte). EXCLUI
-- a Dupla Chance(12): suas 3 saídas não são exaustivas (somam ~2) -> a normalização p/ 1 daria
-- prob ~metade da real; a DC usa dc_devig (derivado do 1X2 da Pinnacle). Os gates de completude
-- Pinnacle por mercado (no mart) seguem barrando linhas sem conjunto Pinnacle completo; só o
-- ramo BTTS usa n_outcomes_valor (consenso).
consensus_devig AS (
    SELECT
        fixture_id, market_id, outcome_side, line_key,
        (1.0 / med_odd) / SUM(1.0 / med_odd) OVER (
            PARTITION BY fixture_id, market_id, line_key
        )                                                         AS cons_prob_justa,
        SUM(1.0 / med_odd) OVER (PARTITION BY fixture_id, market_id, line_key) AS cons_booksum,
        COUNT(*)           OVER (PARTITION BY fixture_id, market_id, line_key) AS cons_n_outcomes
    FROM per_outcome
    WHERE med_odd IS NOT NULL AND med_odd > 0
      AND market_id <> 12
),

-- De-vig da DUPLA CHANCE(12): derivado do de-vig 1X2 da Pinnacle (que JÁ soma 1). As 3 saídas
-- da DC são uniões de 2 das 3 do 1X2, então P(1X)=P(Home)+P(Draw), P(12)=P(Home)+P(Away),
-- P(X2)=P(Draw)+P(Away). Âncora sharp (a Pinnacle precifica o 1X2) — melhor que o consenso, que
-- nem se aplica aqui (saídas não-exaustivas). Exige o conjunto 1X2 inteiro (p_home/draw/away
-- não-NULL); senão a DC fica sem prob_justa e é barrada no gate do mart.
x2_pinnacle AS (
    SELECT
        fixture_id,
        MAX(IF(outcome_side = 'Home', prob_justa_fechamento, NULL)) AS p_home,
        MAX(IF(outcome_side = 'Draw', prob_justa_fechamento, NULL)) AS p_draw,
        MAX(IF(outcome_side = 'Away', prob_justa_fechamento, NULL)) AS p_away,
        ANY_VALUE(pin_n_outcomes)                                  AS n_1x2
    FROM pinnacle_devig
    WHERE market_id = 1
    GROUP BY fixture_id
),
dc_devig AS (
    SELECT
        po.fixture_id, po.market_id, po.outcome_side, po.line_key,
        CASE po.outcome_side
            WHEN '1X' THEN x.p_home + x.p_draw
            WHEN '12' THEN x.p_home + x.p_away
            WHEN 'X2' THEN x.p_draw + x.p_away
        END                                                       AS dc_prob_justa,
        x.n_1x2                                                   AS dc_n_1x2
    FROM per_outcome po
    JOIN x2_pinnacle x ON po.fixture_id = x.fixture_id
    WHERE po.market_id = 12
      AND x.p_home IS NOT NULL AND x.p_draw IS NOT NULL AND x.p_away IS NOT NULL
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
    po.avg_odd_ex_best,
    po.n_casas,
    -- prob_justa/edge: Pinnacle quando há; senão DC derivada do 1X2 (market 12); senão CONSENSO
    -- (mediana das casas). O COALESCE preserva 1X2/O/U/AH (Pinnacle presente -> pd.* não-NULL);
    -- dd só popula no market 12; consenso só "vence" no BTTS etc.
    COALESCE(pd.prob_justa_fechamento, dd.dc_prob_justa, cd.cons_prob_justa) AS prob_justa_fechamento,
    -- booksum Σ(1/odd) (=1+margem) da fonte usada; margem = booksum_fechamento − 1. NULL na DC
    -- (sem booksum: prob derivada do 1X2). Renomeado de "overround" p/ não confundir com a margem.
    COALESCE(pd.booksum_fechamento, cd.cons_booksum)      AS booksum_fechamento,
    pd.pin_n_outcomes,
    -- completude do conjunto usado p/ o VALOR (Pinnacle se há; DC=conjunto 1X2; senão consenso).
    -- O ramo DC do mart gateia por aqui (>=3 = 1X2 completo) e o BTTS (>=2); os ramos com Pinnacle
    -- seguem gateando por pin_n_outcomes.
    COALESCE(pd.pin_n_outcomes, dd.dc_n_1x2, cd.cons_n_outcomes) AS n_outcomes_valor,
    CASE
        WHEN pd.prob_justa_fechamento IS NOT NULL THEN 'pinnacle'
        WHEN dd.dc_prob_justa         IS NOT NULL THEN 'pinnacle'  -- DC derivada do 1X2 (âncora sharp)
        WHEN cd.cons_prob_justa       IS NOT NULL THEN 'consenso'
    END                                                    AS valor_fonte,

    -- edge e PTS_VALOR (0-30). NULL quando não há de-vig (nem Pinnacle, nem DC, nem consenso).
    (po.best_odd * COALESCE(pd.prob_justa_fechamento, dd.dc_prob_justa, cd.cons_prob_justa)) - 1.0 AS edge,
    CAST(ROUND(
        LEAST(GREATEST((po.best_odd * COALESCE(pd.prob_justa_fechamento, dd.dc_prob_justa, cd.cons_prob_justa)) - 1.0, 0) * 100, 6) / 6 * 30
    ) AS INT64) AS pts_valor,

    -- Penalidades globais (flags + total de pontos a subtrair). pen_odd_outlier compara a
    -- best_odd com a média das OUTRAS casas (avg_odd_ex_best, sem a própria best_odd).
    COALESCE(po.best_odd >= 1.10 * po.avg_odd_ex_best, FALSE) AS pen_odd_outlier,
    COALESCE(po.n_casas < 4, FALSE)                   AS pen_poucas_casas,
    COALESCE(po.best_odd > 4.5, FALSE)                AS pen_odd_longshot,
    COALESCE(po.best_odd < 1.40, FALSE)               AS pen_odd_juice,
    (
        30 * CAST(COALESCE(po.best_odd >= 1.10 * po.avg_odd_ex_best, FALSE) AS INT64)
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
LEFT JOIN dc_devig dd
    ON  po.fixture_id   = dd.fixture_id
    AND po.market_id    = dd.market_id
    AND po.outcome_side = dd.outcome_side
    AND po.line_key     = dd.line_key
LEFT JOIN consensus_devig cd
    ON  po.fixture_id   = cd.fixture_id
    AND po.market_id    = cd.market_id
    AND po.outcome_side = cd.outcome_side
    AND po.line_key     = cd.line_key