

WITH predictions AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_predictions`
)

SELECT
    CASE league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        ELSE 'unknown'
    END                                              AS competition,
    league_id,
    season,
    fixture_id,
    kickoff_utc,

    collection_window,
    collection_timestamp,
    DATE(collection_timestamp)                       AS collection_date,
    -- Lead exato da captura (a banda da janela é só rótulo).
    TIMESTAMP_DIFF(kickoff_utc, collection_timestamp, MINUTE) AS minutes_to_kickoff,

    -- previsão (vencedor / placar / conselho)
    predicted_winner_team_id,
    predicted_winner_name,
    predicted_winner_comment,
    predicted_win_or_draw,
    predicted_under_over,
    predicted_goals_home,
    predicted_goals_away,
    advice,

    -- probabilidades 1X2 (%)
    prob_home_pct,
    prob_draw_pct,
    prob_away_pct,

    -- comparação de força home vs away (%)
    comparison_form_home,
    comparison_form_away,
    comparison_att_home,
    comparison_att_away,
    comparison_def_home,
    comparison_def_away,
    comparison_poisson_home,
    comparison_poisson_away,
    comparison_h2h_home,
    comparison_h2h_away,
    comparison_goals_home,
    comparison_goals_away,
    comparison_total_home,
    comparison_total_away,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM predictions
-- Dedup latest-wins por fixture: várias capturas/jogo (daily 1x/dia + t2h) → fica a mais fresca.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY fixture_id
    ORDER BY loaded_at DESC
) = 1