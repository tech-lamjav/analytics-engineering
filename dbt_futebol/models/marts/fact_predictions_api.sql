{{ config(
    materialized='table',
    partition_by={'field': 'collection_date', 'data_type': 'date'},
    cluster_by=['fixture_id'],
    description='BASELINE de comparação: previsão pré-jogo do algoritmo da própria API-Football (/predictions) — 1 linha por fixture. Guarda probabilidades 1X2 (prob_*_pct), vencedor/placar/conselho previstos e a comparação de força home vs away (comparison_* = form/att/def/poisson/h2h/goals/total). Uso: avaliar se um modelo próprio bate a API consistentemente (= edge real); NÃO é produto. FORWARD-ONLY: o raw acumula no GCS (1 arquivo por fixture×janela×dia, date-stampado — janela "daily" varre jogos futuros 1x/dia até 14d + "t2h" perto do jogo) e o rebuild full lê tudo. Self-contained: competition vem de league_id, sem joins. Particionada por collection_date (=DATE(collection_timestamp)) e clusterizada por fixture_id. minutes_to_kickoff = lead exato da captura. Dedup latest-wins por fixture_id (QUALIFY ORDER BY loaded_at DESC — load-bearing: escolhe o snapshot mais fresco entre as várias capturas/jogo). Brasileirão (71) + Copa do Mundo (1) + Série B (72) + Copa do Brasil (73) + CONMEBOL Libertadores (13) + CONMEBOL Sudamericana (11) 2026 (todos coverage.predictions=TRUE; na Copa do Brasil as previsões de mata-mata são reais — validado 2026-07-10, sem o placeholder 45/45/10 visto na Copa do Mundo; na Libertadores a janela daily de 14d só alcança as oitavas ~28/07; na Sudamericana a R32 de 21–31/07 JÁ está na janela — conferir na 1ª captura de cada uma se vem real ou placeholder).'
) }}

WITH predictions AS (
    SELECT * FROM {{ ref('stg_futebol_predictions') }}
)

SELECT
    CASE league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        WHEN 72 THEN 'serie_b'
        WHEN 73 THEN 'copa_do_brasil'
        WHEN 13 THEN 'libertadores'
        WHEN 11 THEN 'sudamericana'
        WHEN 140 THEN 'la_liga'
        WHEN 39 THEN 'premier_league'
        WHEN 2  THEN 'champions_league'
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
