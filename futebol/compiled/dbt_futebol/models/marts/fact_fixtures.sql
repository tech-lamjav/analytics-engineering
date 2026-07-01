

SELECT
    fixture_id,
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
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
-- Defensivo: fixture_id já é único (backfill/current não sobrepõem liga-temporada).
-- Mantém o idioma de dedup de dim_players/dim_teams.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY fixture_id
    ORDER BY loaded_at DESC
) = 1