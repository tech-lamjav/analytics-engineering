{{ config(
    materialized='table',
    cluster_by=['competition', 'fixture_id'],
    description='Mart de saída do Motor de Score de Confiabilidade (value bet futebol). 1 linha por (fixture_id, market, outcome, line_value) que PASSA no gate (edge>0 E n_casas>=3 E de-vig válido E conjunto da Pinnacle completo pro mercado E score>=40 E — p/ Handicap asiático/Gols O/U — linha meia .5, sem push). Score 0-100 = clamp(PTS_VALOR + PTS_PREMISSAS + PTS_CORROBORACAO − PENALIDADES). faixa Alta(>=60)/Média(40-59); abaixo de 40 não vira oportunidade. evidencias[] = o "por quê" (premissas + corroboração); avisos[] = red flags. Long por `market` — v5 liga 1X2 (market_id=1) + Gols O/U (market_id=5) + Handicap asiático (market_id=4) + Ambos Marcam/BTTS (market_id=8) + Dupla Chance (market_id=12, saídas 1X/X2). Junta int_futebol_premissas_1x2/_ou/_ah/_btts/_dc + int_futebol_odds_devig + int_futebol_corroboracao. line_value é NULL no 1X2/BTTS/DC, a linha L no O/U e o handicap (ótica do mandante, mesmo p/ Home e Away) no AH. valor_fonte = pinnacle (de-vig da Pinnacle, mercados 1/4/5; e DC, derivada do 1X2 da Pinnacle) ou consenso (de-vig da mediana das casas — BTTS, pois a Pinnacle não precifica; rotular como estimativa no front). A DC tem GATE PRÓPRIO (melhor_odd >=1,25, sem odd_juice) — aplicado no ramo joined_dc; o gate >=1,25 já garante o retorno mínimo (sem penalidade específica de odd baixa).'
) }}

WITH prem_1x2 AS (
    SELECT * FROM {{ ref('int_futebol_premissas_1x2') }}
),

prem_ou AS (
    SELECT * FROM {{ ref('int_futebol_premissas_ou') }}
),

prem_ah AS (
    SELECT * FROM {{ ref('int_futebol_premissas_ah') }}
),

prem_btts AS (
    SELECT * FROM {{ ref('int_futebol_premissas_btts') }}
),

prem_dc AS (
    SELECT * FROM {{ ref('int_futebol_premissas_dc') }}
),

-- line_key STRING (NULL-safe) p/ casar a linha entre modelos sem depender de igualdade FLOAT.
devig AS (
    SELECT *, COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM {{ ref('int_futebol_odds_devig') }}
),

corro AS (
    SELECT *, COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM {{ ref('int_futebol_corroboracao') }}
),

-- ============================================================================
-- Ramo 1X2 (market_id=1): casa por (fixture, outcome_side); line_value é NULL.
-- Gate de completude do de-vig = conjunto 1X2 inteiro na Pinnacle (3 outcomes).
-- ============================================================================
joined_1x2 AS (
    SELECT
        p.fixture_id,
        'match_winner'                          AS market,
        p.outcome,
        CAST(NULL AS FLOAT64)                   AS line_value,
        p.competition,
        p.season,

        d.edge,
        COALESCE(d.pts_valor, 0)                AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.valor_fonte,
        d.janela_usada,
        COALESCE(d.penalidades_globais_pts, 0)  AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.penalidades_1x2_pts                   AS penalidades_especificas_pts,
        p.evidencias                            AS evidencias_premissas,
        p.avisos                                AS avisos_especificos,

        COALESCE(c.pts_corroboracao, 0)         AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)  AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE) AS linha_sharp_confirma
    FROM prem_1x2 p
    INNER JOIN devig d
        ON d.market_id = 1
       AND d.fixture_id = p.fixture_id
       AND d.outcome_side = p.outcome
    LEFT JOIN corro c
        ON c.market_id = 1
       AND c.fixture_id = p.fixture_id
       AND c.outcome_side = p.outcome
    WHERE d.pin_n_outcomes >= 3
),

-- ============================================================================
-- Ramo Gols O/U (market_id=5): casa por (fixture, outcome_side, line_key STRING).
-- Gate de completude do de-vig = par Over+Under da Pinnacle na linha (2 outcomes).
-- ============================================================================
joined_ou AS (
    SELECT
        p.fixture_id,
        'goals_over_under'                      AS market,
        p.outcome,
        p.line_value,
        p.competition,
        p.season,

        d.edge,
        COALESCE(d.pts_valor, 0)                AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.valor_fonte,
        d.janela_usada,
        COALESCE(d.penalidades_globais_pts, 0)  AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.penalidades_ou_pts                    AS penalidades_especificas_pts,
        p.evidencias                            AS evidencias_premissas,
        p.avisos                                AS avisos_especificos,

        COALESCE(c.pts_corroboracao, 0)         AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)  AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE) AS linha_sharp_confirma
    FROM prem_ou p
    INNER JOIN devig d
        ON d.market_id = 5
       AND d.fixture_id = p.fixture_id
       AND d.outcome_side = p.outcome
       AND d.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
    LEFT JOIN corro c
        ON c.market_id = 5
       AND c.fixture_id = p.fixture_id
       AND c.outcome_side = p.outcome
       AND c.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
    WHERE d.pin_n_outcomes >= 2
),

-- ============================================================================
-- Ramo Handicap asiático (market_id=4): casa por (fixture, outcome_side, line_value).
-- line_value é o handicap na ÓTICA DO MANDANTE e é o MESMO p/ Home e Away (par
-- complementar) — o de-vig já normaliza Home+Away por (fixture, market, line) com 2 outcomes.
-- Gate de completude = par da Pinnacle (>=2 outcomes), igual ao O/U.
-- ============================================================================
joined_ah AS (
    SELECT
        p.fixture_id,
        'asian_handicap'                        AS market,
        p.outcome,
        p.line_value,
        p.competition,
        p.season,

        d.edge,
        COALESCE(d.pts_valor, 0)                AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.valor_fonte,
        d.janela_usada,
        COALESCE(d.penalidades_globais_pts, 0)  AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.penalidades_ah_pts                    AS penalidades_especificas_pts,
        p.evidencias                            AS evidencias_premissas,
        p.avisos                                AS avisos_especificos,

        COALESCE(c.pts_corroboracao, 0)         AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)  AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE) AS linha_sharp_confirma
    FROM prem_ah p
    INNER JOIN devig d
        ON d.market_id = 4
       AND d.fixture_id = p.fixture_id
       AND d.outcome_side = p.outcome
       AND d.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
    LEFT JOIN corro c
        ON c.market_id = 4
       AND c.fixture_id = p.fixture_id
       AND c.outcome_side = p.outcome
       AND c.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
    WHERE d.pin_n_outcomes >= 2
),

-- ============================================================================
-- Ramo Ambos Marcam / BTTS (market_id=8): casa por (fixture, outcome_side); line_value NULL
-- (como o 1X2). A Pinnacle NÃO precifica BTTS -> o de-vig usa CONSENSO (valor_fonte='consenso',
-- prob_justa/edge = mediana das casas). Gate de completude = par Yes+No no consenso, via
-- n_outcomes_valor (>=2). pin_n_outcomes fica NULL (honesto: não houve Pinnacle).
-- ============================================================================
joined_btts AS (
    SELECT
        p.fixture_id,
        'btts'                                  AS market,
        p.outcome,
        CAST(NULL AS FLOAT64)                   AS line_value,
        p.competition,
        p.season,

        d.edge,
        COALESCE(d.pts_valor, 0)                AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.valor_fonte,
        d.janela_usada,
        COALESCE(d.penalidades_globais_pts, 0)  AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.penalidades_btts_pts                  AS penalidades_especificas_pts,
        p.evidencias                            AS evidencias_premissas,
        p.avisos                                AS avisos_especificos,

        COALESCE(c.pts_corroboracao, 0)         AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)  AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE) AS linha_sharp_confirma
    FROM prem_btts p
    INNER JOIN devig d
        ON d.market_id = 8
       AND d.fixture_id = p.fixture_id
       AND d.outcome_side = p.outcome
    LEFT JOIN corro c
        ON c.market_id = 8
       AND c.fixture_id = p.fixture_id
       AND c.outcome_side = p.outcome
    WHERE d.n_outcomes_valor >= 2
),

-- ============================================================================
-- Ramo Dupla Chance (market_id=12): casa por (fixture, outcome_side); line_value NULL.
-- Saídas 1X (Home+Draw) e X2 (Draw+Away). A Pinnacle não precifica DC, mas a prob_justa é
-- DERIVADA do de-vig 1X2 da Pinnacle (valor_fonte='pinnacle') — gate de completude =
-- conjunto 1X2 inteiro (n_outcomes_valor>=3). GATE PRÓPRIO: aceita melhor_odd >= 1,25 e NÃO
-- aplica odd_juice (<1,40); o próprio gate >=1,25 já garante o retorno mínimo (sem penalidade
-- específica de odd baixa — a antiga odd_muito_baixa<1,20 era inalcançável sob esse gate).
-- ============================================================================
joined_dc AS (
    SELECT
        p.fixture_id,
        'double_chance'                         AS market,
        p.outcome,
        CAST(NULL AS FLOAT64)                   AS line_value,
        p.competition,
        p.season,

        d.edge,
        COALESCE(d.pts_valor, 0)                AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.valor_fonte,
        d.janela_usada,
        -- penalidades globais SEM odd_juice (a DC tem gate de odd próprio).
        ( 30 * CAST(d.pen_odd_outlier  AS INT64)
        + 12 * CAST(d.pen_poucas_casas AS INT64)
        + 15 * CAST(d.pen_odd_longshot AS INT64) ) AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        FALSE                                   AS pen_odd_juice,  -- DC nunca aplica juice

        p.pts_premissas,
        -- DC não tem penalidade específica: o gate de odd próprio (melhor_odd >= 1,25) já
        -- barra o retorno baixo. A antiga penalidade odd_muito_baixa (<1,20) era código morto
        -- — inalcançável sob o gate >=1,25 (best_odd<1,20 sempre FALSE) -> removida (#8).
        CAST(0 AS INT64)                        AS penalidades_especificas_pts,
        p.evidencias                            AS evidencias_premissas,
        p.avisos                                AS avisos_especificos,

        COALESCE(c.pts_corroboracao, 0)         AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)  AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE) AS linha_sharp_confirma
    FROM prem_dc p
    INNER JOIN devig d
        ON d.market_id = 12
       AND d.fixture_id = p.fixture_id
       AND d.outcome_side = p.outcome
    LEFT JOIN corro c
        ON c.market_id = 12
       AND c.fixture_id = p.fixture_id
       AND c.outcome_side = p.outcome
    WHERE d.n_outcomes_valor >= 3   -- conjunto 1X2 da Pinnacle completo (derivação válida)
      AND d.best_odd >= 1.25        -- gate de odd próprio da DC (sem juice)
),

unioned AS (
    SELECT * FROM joined_1x2
    UNION ALL
    SELECT * FROM joined_ou
    UNION ALL
    SELECT * FROM joined_ah
    UNION ALL
    SELECT * FROM joined_btts
    UNION ALL
    SELECT * FROM joined_dc
),

scored AS (
    SELECT
        *,
        (penalidades_globais_pts + penalidades_especificas_pts) AS penalidades,
        LEAST(GREATEST(
            pts_valor + pts_premissas + pts_corroboracao
            - (penalidades_globais_pts + penalidades_especificas_pts), 0), 100) AS score,
        -- #2: linha "meia" (.5) é a única SEM push/meio-push. line_value*2 ímpar => meia.
        -- TRUE só p/ .5; FALSE p/ linha cheia (2.0) e quarter; NULL onde não há linha (1X2/BTTS/DC).
        (MOD(CAST(ROUND(ABS(line_value) * 2) AS INT64), 2) = 1) AS is_half_line
    FROM unioned
)

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    competition,
    season,

    edge,
    pts_valor,
    pts_premissas,
    pts_corroboracao,
    penalidades,
    score,
    CASE
        WHEN score >= 60 THEN 'Alta'
        WHEN score >= 40 THEN 'Média'
        ELSE 'Baixa'
    END AS faixa,

    -- "por quê": premissas que dispararam + corroboração confirmada.
    ARRAY_CONCAT(
        evidencias_premissas,
        ARRAY(SELECT x FROM UNNEST([
            IF(modelo_api_concorda, 'modelo da API concorda com o lado (+7)', NULL),
            IF(linha_sharp_confirma, 'linha da Pinnacle se moveu pro nosso lado (+8)', NULL)
        ]) AS x WHERE x IS NOT NULL)
    ) AS evidencias,

    -- avisos: penalidades específicas do mercado + penalidades globais de odds.
    ARRAY_CONCAT(
        avisos_especificos,
        ARRAY(SELECT y FROM UNNEST([
            IF(pen_odd_outlier,  '⚠ odd fora da média — provável linha mole/erro (−30)', NULL),
            IF(pen_poucas_casas, '⚠ poucas casas cobrindo o mercado (−12)', NULL),
            IF(pen_odd_longshot, '⚠ odd muito alta / longshot (−15)', NULL),
            IF(pen_odd_juice,    '⚠ retorno baixo / juice (−10)', NULL)
        ]) AS y WHERE y IS NOT NULL)
    ) AS avisos,

    -- contexto de odds
    best_odd,
    best_book,
    avg_odd,
    n_casas,
    prob_justa_fechamento,
    valor_fonte,
    janela_usada,

    -- componentes (transparência/debug)
    penalidades_globais_pts,
    penalidades_especificas_pts,
    modelo_api_concorda,
    linha_sharp_confirma,
    pin_n_outcomes,
    is_half_line,
    -- #2: para rankear por VALOR use `edge` (o score/faixa é índice de CONFIANÇA, não monotônico
    -- no edge — um bet de 1% de edge pode ter score maior que um de 6%). Sem coluna ev_rank dedicada.

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
-- Gate (a completude da Pinnacle por mercado já foi aplicada por ramo: 1X2 >=3 outcomes,
-- O/U e AH >=2). Aqui: edge positivo, mercado líquido (>=3 casas), de-vig válido E score>=40
-- (#c: honra o contrato "abaixo de 40 não vira oportunidade"). #2: exclui linha NÃO-meia
-- (cheia/quarter) de Handicap asiático e Gols O/U — nessas o resultado pode dar push/meio-push
-- e o de-vig 2-way superdimensiona o edge; mercados sem linha (1X2/BTTS/DC) passam direto.
WHERE edge > CASE
               -- #1: edge de CONSENSO (BTTS — Pinnacle não precifica) é enviesado p/ cima
               -- (best_odd=MAX das casas vs prob da MEDIANA) -> exige piso de edge maior.
               -- Conservador e TUNÁVEL via var consensus_min_edge (default 0.03 = 3%).
               WHEN valor_fonte = 'consenso' THEN {{ var('consensus_min_edge', 0.03) }}
               ELSE 0
             END
  AND n_casas >= 3
  AND prob_justa_fechamento IS NOT NULL
  AND score >= 40
  AND (market NOT IN ('asian_handicap', 'goals_over_under') OR is_half_line)
