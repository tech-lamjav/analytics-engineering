{{ config(
    materialized='view',
    description='Fase 0 do Motor de Score — CORROBORAÇÃO externa (0-15), por (fixture_id, market_id, outcome_side, line_value). modelo_api_concorda (+7): o /predictions da própria API aponta o mesmo lado (hoje só implementado p/ 1X2; predictions ~vazio até a S6 coletar fixtures futuros -> majoritariamente FALSE, graceful). linha_sharp_confirma (+8): reusa o sinal já calculado no int_futebol_odds_devig (Pinnacle caiu t24h->t15m).'
) }}

WITH devig AS (
    SELECT fixture_id, market_id, outcome_side, line_value, linha_sharp_confirma
    FROM {{ ref('int_futebol_odds_devig') }}
),

fixtures AS (
    SELECT fixture_id, home_team_id, away_team_id
    FROM {{ ref('fact_fixtures') }}
),

preds AS (
    SELECT
        fixture_id,
        predicted_winner_team_id,
        prob_home_pct,
        prob_draw_pct,
        prob_away_pct
    FROM {{ ref('fact_predictions_api') }}
),

joined AS (
    SELECT
        d.fixture_id,
        d.market_id,
        d.outcome_side,
        d.line_value,
        d.linha_sharp_confirma,
        -- modelo_api_concorda só p/ 1X2 nesta versão.
        -- TODO(S2+): mapear predicted_under_over (O/U) e demais mercados a outcome_side.
        CASE
            WHEN d.market_id = 1 AND d.outcome_side = 'Home'
                THEN COALESCE(p.predicted_winner_team_id = f.home_team_id, FALSE)
            WHEN d.market_id = 1 AND d.outcome_side = 'Away'
                THEN COALESCE(p.predicted_winner_team_id = f.away_team_id, FALSE)
            WHEN d.market_id = 1 AND d.outcome_side = 'Draw'
                THEN COALESCE(
                        p.prob_draw_pct >= p.prob_home_pct
                    AND p.prob_draw_pct >= p.prob_away_pct, FALSE)
            ELSE FALSE
        END AS modelo_api_concorda
    FROM devig d
    LEFT JOIN fixtures f ON d.fixture_id = f.fixture_id
    LEFT JOIN preds    p ON d.fixture_id = p.fixture_id
)

SELECT
    fixture_id,
    market_id,
    outcome_side,
    line_value,
    modelo_api_concorda,
    linha_sharp_confirma,
    (7 * CAST(modelo_api_concorda AS INT64)
   + 8 * CAST(linha_sharp_confirma AS INT64)) AS pts_corroboracao,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM joined
