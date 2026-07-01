{{ config(
    materialized='view',
    description='S7 do Motor de Score — desfalques por (fixture, time, jogador) com TIPO + flag de IMPORTÂNCIA. Artefato do aceite da S7 ("lista de desfalques por time, cada um com tipo fora/dúvida e flag titular sim/não"). Snapshot MAIS RECENTE por fixture (MAX(snapshot_date)) de fact_injuries_snapshot, colapsado a 1 linha por (fixture, team, player) preferindo Missing Fixture a Questionable — resolve a divergência de (type, reason) entre o poll por fixture e o season-log (guard de double-count: + teste de uniqueness). Juntado ao proxy int_futebol_player_importance por (player_id, competition_id = league_id) — join por player+competição (NÃO team_id) lida com transferências entre clubes BR. is_important COALESCE FALSE (degradação graciosa: jogador sem histórico). Consumido por int_futebol_premissas_1x2 (só Missing Fixture AND is_important dispara desfalque). ⚠️ Coverage: só Brasileirão (injuries=TRUE); Copa não gera linhas.'
) }}

WITH inj_latest AS (
    SELECT
        fixture_id,
        team_id,
        player_id,
        player_name,
        injury_type,
        injury_reason,
        league_id
    FROM {{ ref('fact_injuries_snapshot') }}
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
    FROM {{ ref('int_futebol_player_importance') }}
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
