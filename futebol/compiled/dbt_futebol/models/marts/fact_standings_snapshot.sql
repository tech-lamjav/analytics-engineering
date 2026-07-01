

WITH standings AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_standings`
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
    rank,
    points,
    goals_diff,
    group_name,
    form,
    rank_status,
    rank_description,
    standings_updated_at,

    -- campanha geral
    played_total,
    wins_total,
    draws_total,
    loses_total,
    goals_for_total,
    goals_against_total,

    -- campanha como mandante
    played_home,
    wins_home,
    draws_home,
    loses_home,
    goals_for_home,
    goals_against_home,

    -- campanha como visitante
    played_away,
    wins_away,
    draws_away,
    loses_away,
    goals_for_away,
    goals_against_away,

    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM standings
-- Idempotência: re-run no mesmo dia sobrescreve o arquivo no GCS e o dedup
-- segura qualquer resíduo. group_name na chave: na Copa o mesmo time aparece
-- no grupo E no "Ranking of third-placed teams" — são duas linhas legítimas.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY requested_league_id, requested_season, snapshot_date, group_name, team_id
    ORDER BY loaded_at DESC
) = 1