

SELECT
    fixture_id,
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        WHEN 72 THEN 'serie_b'
        WHEN 73 THEN 'copa_do_brasil'
        WHEN 13 THEN 'libertadores'
        WHEN 11 THEN 'sudamericana'
        WHEN 140 THEN 'la_liga'
        WHEN 39 THEN 'premier_league'
        WHEN 2  THEN 'champions_league'
        WHEN 135 THEN 'serie_a_ita'
        WHEN 78  THEN 'bundesliga'
        WHEN 61  THEN 'ligue_1'
        WHEN 94  THEN 'primeira_liga'
        ELSE 'unknown'
    END                                          AS competition,
    requested_league_id                          AS competition_id,
    requested_season                             AS season,
    round,

    -- tempo (epoch UTC = inequívoco; date_utc é a chave de partição)
    DATE(TIMESTAMP_SECONDS(timestamp_unix))      AS date_utc,
    TIMESTAMP_SECONDS(timestamp_unix)            AS kickoff_utc,
    timestamp_unix,
    timezone,

    -- status do jogo
    status_long,
    status_short,
    status_elapsed,

    -- local / arbitragem
    referee,
    venue_id,
    venue_name,
    venue_city,

    -- times (home_team_id participa do cluster)
    home_team_id,
    home_team_name,
    home_team_winner,
    away_team_id,
    away_team_name,
    away_team_winner,

    -- placar
    goals_home,
    goals_away,
    score_halftime_home,
    score_halftime_away,
    score_fulltime_home,
    score_fulltime_away,
    score_extratime_home,
    score_extratime_away,
    score_penalty_home,
    score_penalty_away,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixtures`
-- NÃO é defensivo: fixture_id NÃO é único em stg_futebol_fixtures (o extractor
-- re-busca jogo recente e a mesma fixture entra de novo com loaded_at maior — corrigido
-- na description do modelo em 02/09/2026). Este QUALIFY é o dedup de verdade, latest-wins
-- por loaded_at. Mantém o idioma de dedup de dim_players/dim_teams.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY fixture_id
    ORDER BY loaded_at DESC
) = 1