

WITH devig AS (
    SELECT fixture_id, market_id, outcome_side, line_value, linha_sharp_confirma
    FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
),

preds AS (
    SELECT
        fixture_id,
        prob_home_pct,
        prob_draw_pct,
        prob_away_pct
    FROM `smartbetting-dados`.`futebol`.`fact_predictions_api`
),

joined AS (
    SELECT
        d.fixture_id,
        d.market_id,
        d.outcome_side,
        d.line_value,
        d.linha_sharp_confirma,
        -- modelo_api_concorda só p/ 1X2 nesta versão. Base ÚNICA p/ os 3 lados = ARGMAX das
        -- probabilidades da API -> no máx. 1 lado concorda por fixture. (Antes Home/Away usavam
        -- predicted_winner_team_id e só o Draw o argmax: um time E o empate podiam concordar.)
        -- TODO(S2+): mapear predicted_under_over (O/U) e demais mercados a outcome_side.
        CASE
            WHEN d.market_id = 1 AND d.outcome_side = 'Home'
                THEN COALESCE(
                        p.prob_home_pct >= p.prob_draw_pct
                    AND p.prob_home_pct >= p.prob_away_pct, FALSE)
            WHEN d.market_id = 1 AND d.outcome_side = 'Away'
                THEN COALESCE(
                        p.prob_away_pct >= p.prob_home_pct
                    AND p.prob_away_pct >= p.prob_draw_pct, FALSE)
            WHEN d.market_id = 1 AND d.outcome_side = 'Draw'
                THEN COALESCE(
                        p.prob_draw_pct >= p.prob_home_pct
                    AND p.prob_draw_pct >= p.prob_away_pct, FALSE)
            ELSE FALSE
        END AS modelo_api_concorda
    FROM devig d
    LEFT JOIN preds p ON d.fixture_id = p.fixture_id
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