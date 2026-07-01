

WITH injuries AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_injuries`
)

SELECT
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        ELSE 'unknown'
    END                                          AS competition,
    requested_league_id                          AS league_id,
    requested_season                             AS season,
    snapshot_date,

    team_id,
    team_name,
    team_logo,

    player_id,
    player_name,
    player_photo,

    fixture_id,
    fixture_date,

    injury_type,
    injury_reason,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM injuries
-- Idempotência + dedup das linhas EXATAS que a API repete: granularidade = 1 linha por
-- (player, fixture, type, reason) por snapshot. Re-run no mesmo dia sobrescreve o arquivo
-- no GCS e o QUALIFY segura qualquer resíduo.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY requested_league_id, requested_season, snapshot_date,
                 fixture_id, player_id, injury_type, injury_reason
    ORDER BY loaded_at DESC
) = 1