

WITH inj_latest AS (
    SELECT
        fixture_id,
        team_id,
        player_id,
        player_name,
        injury_type,
        injury_reason,
        league_id
    FROM `smartbetting-dados`.`futebol`.`fact_injuries_snapshot`
    -- snapshot mais recente por fixture (o histórico acumula no fato; o desfalque "vigente" é o último).
    QUALIFY snapshot_date = MAX(snapshot_date) OVER (PARTITION BY fixture_id)
),

-- 1 linha por (fixture, team, player): se a API trouxe (Missing Fixture) E (Questionable)
-- p/ o mesmo jogador, fica o Missing Fixture (status mais severo p/ a premissa).
inj_dedup AS (
    SELECT *
    FROM inj_latest
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, team_id, player_id
        ORDER BY (injury_type = 'Missing Fixture') DESC, injury_reason
    ) = 1
),

importance AS (
    SELECT
        player_id,
        competition_id,
        is_important,
        start_share,
        total_minutes,
        avg_rating,
        games
    FROM `smartbetting-dados`.`futebol`.`int_futebol_player_importance`
)

SELECT
    i.fixture_id,
    i.team_id,
    i.player_id,
    i.player_name,
    i.injury_type,                       -- 'Missing Fixture' (fora) | 'Questionable' (dúvida)
    i.injury_reason,
    COALESCE(imp.is_important, FALSE)  AS is_important,
    imp.start_share,
    imp.total_minutes,
    imp.avg_rating,
    COALESCE(imp.games, 0)             AS importance_games,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM inj_dedup i
LEFT JOIN importance imp
    ON  imp.player_id = i.player_id
    AND imp.competition_id = i.league_id