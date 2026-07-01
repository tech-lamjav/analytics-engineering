

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_predictions`
)

SELECT
    src.fixture_id,
    src.league_id,
    src.season,
    src.collection_window,
    src.collection_timestamp,
    TIMESTAMP_SECONDS(src.kickoff_timestamp) AS kickoff_utc,
    src.loaded_at,

    -- predictions: vencedor previsto, conselho (texto) e linhas de gol (STRING "-1.5")
    src.predictions.winner.id      AS predicted_winner_team_id,
    src.predictions.winner.name    AS predicted_winner_name,
    src.predictions.winner.comment AS predicted_winner_comment,
    src.predictions.win_or_draw    AS predicted_win_or_draw,
    SAFE_CAST(src.predictions.under_over AS FLOAT64) AS predicted_under_over,
    SAFE_CAST(src.predictions.goals.home AS FLOAT64) AS predicted_goals_home,
    SAFE_CAST(src.predictions.goals.away AS FLOAT64) AS predicted_goals_away,
    src.predictions.advice         AS advice,

    -- probabilidades 1X2 (percentuais "45%" → FLOAT)
    SAFE_CAST(REPLACE(src.predictions.percent.home, '%', '') AS FLOAT64) AS prob_home_pct,
    SAFE_CAST(REPLACE(src.predictions.percent.draw, '%', '') AS FLOAT64) AS prob_draw_pct,
    SAFE_CAST(REPLACE(src.predictions.percent.away, '%', '') AS FLOAT64) AS prob_away_pct,

    -- comparison: força relativa home vs away (todos percentuais "45%" → FLOAT)
    SAFE_CAST(REPLACE(src.comparison.form.home, '%', '') AS FLOAT64) AS comparison_form_home,
    SAFE_CAST(REPLACE(src.comparison.form.away, '%', '') AS FLOAT64) AS comparison_form_away,
    SAFE_CAST(REPLACE(src.comparison.att.home, '%', '') AS FLOAT64) AS comparison_att_home,
    SAFE_CAST(REPLACE(src.comparison.att.away, '%', '') AS FLOAT64) AS comparison_att_away,
    SAFE_CAST(REPLACE(src.comparison.`def`.home, '%', '') AS FLOAT64) AS comparison_def_home,
    SAFE_CAST(REPLACE(src.comparison.`def`.away, '%', '') AS FLOAT64) AS comparison_def_away,
    SAFE_CAST(REPLACE(src.comparison.poisson_distribution.home, '%', '') AS FLOAT64) AS comparison_poisson_home,
    SAFE_CAST(REPLACE(src.comparison.poisson_distribution.away, '%', '') AS FLOAT64) AS comparison_poisson_away,
    SAFE_CAST(REPLACE(src.comparison.h2h.home, '%', '') AS FLOAT64) AS comparison_h2h_home,
    SAFE_CAST(REPLACE(src.comparison.h2h.away, '%', '') AS FLOAT64) AS comparison_h2h_away,
    SAFE_CAST(REPLACE(src.comparison.goals.home, '%', '') AS FLOAT64) AS comparison_goals_home,
    SAFE_CAST(REPLACE(src.comparison.goals.away, '%', '') AS FLOAT64) AS comparison_goals_away,
    SAFE_CAST(REPLACE(src.comparison.total.home, '%', '') AS FLOAT64) AS comparison_total_home,
    SAFE_CAST(REPLACE(src.comparison.total.away, '%', '') AS FLOAT64) AS comparison_total_away
FROM src
-- Defensivo: ignora eventual linha metadata-only (arquivo subido sem previsão)
WHERE src.fixture_id IS NOT NULL