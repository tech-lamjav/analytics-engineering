{{ config(
    materialized='table',
    cluster_by=['competition', 'fixture_id'],
    description='Mart de saída do Motor de Score de Confiabilidade (value bet futebol). 1 linha por (fixture_id, market, outcome, line_value) que PASSA no gate (edge>0 E n_casas>=3 E de-vig válido E conjunto da Pinnacle completo pro mercado). Score 0-100 = clamp(PTS_VALOR + PTS_PREMISSAS + PTS_CORROBORACAO − PENALIDADES). faixa Alta(>=60)/Média(40-59); abaixo de 40 não vira oportunidade. evidencias[] = o "por quê" (premissas + corroboração); avisos[] = red flags. Long por `market` — v2 liga 1X2 (market_id=1) + Gols O/U (market_id=5); S3-S5 dão UNION depois. Junta int_futebol_premissas_1x2/_ou + int_futebol_odds_devig + int_futebol_corroboracao. line_value é NULL no 1X2 e a linha L (1.5/2.5/3.5/...) no O/U.'
) }}

WITH prem_1x2 AS (
    SELECT * FROM {{ ref('int_futebol_premissas_1x2') }}
),

prem_ou AS (
    SELECT * FROM {{ ref('int_futebol_premissas_ou') }}
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

unioned AS (
    SELECT * FROM joined_1x2
    UNION ALL
    SELECT * FROM joined_ou
),

scored AS (
    SELECT
        *,
        (penalidades_globais_pts + penalidades_especificas_pts) AS penalidades,
        LEAST(GREATEST(
            pts_valor + pts_premissas + pts_corroboracao
            - (penalidades_globais_pts + penalidades_especificas_pts), 0), 100) AS score
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
    janela_usada,

    -- componentes (transparência/debug)
    penalidades_globais_pts,
    penalidades_especificas_pts,
    modelo_api_concorda,
    linha_sharp_confirma,
    pin_n_outcomes,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
-- Gate (market-agnóstico aqui; a completude da Pinnacle por mercado já foi aplicada por ramo:
-- 1X2 >=3 outcomes, O/U >=2): edge positivo, mercado líquido (>=3 casas) e de-vig válido.
WHERE edge > 0
  AND n_casas >= 3
  AND prob_justa_fechamento IS NOT NULL
