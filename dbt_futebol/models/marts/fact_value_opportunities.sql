{{ config(
    materialized='table',
    cluster_by=['competition', 'fixture_id'],
    description='Mart de saída do Motor de Score de Confiabilidade (value bet futebol). 1 linha por (fixture_id, market, outcome) que PASSA no gate (edge>0 E n_casas>=3 E de-vig válido). Score 0-100 = clamp(PTS_VALOR + PTS_PREMISSAS + PTS_CORROBORACAO − PENALIDADES). faixa Alta(>=60)/Média(40-59); abaixo de 40 não vira oportunidade. evidencias[] = o "por quê" (premissas + corroboração); avisos[] = red flags. Long por `market` — v1 liga só 1X2 (market_id=1); S2-S5 dão UNION depois. Junta int_futebol_premissas_1x2 + int_futebol_odds_devig + int_futebol_corroboracao.'
) }}

WITH premissas AS (
    SELECT * FROM {{ ref('int_futebol_premissas_1x2') }}
),

devig AS (
    SELECT * FROM {{ ref('int_futebol_odds_devig') }}
    WHERE market_id = 1
),

corro AS (
    SELECT * FROM {{ ref('int_futebol_corroboracao') }}
    WHERE market_id = 1
),

joined AS (
    SELECT
        p.fixture_id,
        'match_winner'                          AS market,
        p.outcome,
        p.competition,
        p.season,

        -- valor / odds
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

        -- premissas
        p.pts_premissas,
        p.penalidades_1x2_pts,
        p.evidencias                            AS evidencias_premissas,
        p.avisos                                AS avisos_1x2,

        -- corroboração
        COALESCE(c.pts_corroboracao, 0)         AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)  AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE) AS linha_sharp_confirma
    FROM premissas p
    INNER JOIN devig d
        ON d.fixture_id = p.fixture_id AND d.outcome_side = p.outcome
    LEFT JOIN corro c
        ON c.fixture_id = p.fixture_id AND c.outcome_side = p.outcome
),

scored AS (
    SELECT
        *,
        (penalidades_globais_pts + penalidades_1x2_pts) AS penalidades,
        LEAST(GREATEST(
            pts_valor + pts_premissas + pts_corroboracao
            - (penalidades_globais_pts + penalidades_1x2_pts), 0), 100) AS score
    FROM joined
)

SELECT
    fixture_id,
    market,
    outcome,
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

    -- avisos: penalidades específicas (1X2) + penalidades globais de odds.
    ARRAY_CONCAT(
        avisos_1x2,
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
    penalidades_1x2_pts,
    modelo_api_concorda,
    linha_sharp_confirma,
    pin_n_outcomes,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
-- Gate: só é oportunidade com edge positivo, mercado líquido (>=3 casas) e de-vig válido
-- (conjunto 1X2 completo na Pinnacle = 3 outcomes).
WHERE edge > 0
  AND n_casas >= 3
  AND prob_justa_fechamento IS NOT NULL
  AND pin_n_outcomes >= 3
