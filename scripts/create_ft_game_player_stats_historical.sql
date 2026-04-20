-- =============================================================================
-- ft_game_player_stats_historical
-- Tabela histórica de stats por jogo/jogador cobrindo múltiplas temporadas.
-- Script de execução única — não é um modelo dbt.
-- Executar via: bq query --use_legacy_sql=false < create_ft_game_player_stats_historical.sql
-- =============================================================================

-- Passo 1: Criar external table cobrindo todas as temporadas disponíveis no GCS
CREATE OR REPLACE EXTERNAL TABLE `smartbetting-dados.nba.raw_game_player_stats_all_seasons`
  OPTIONS (
    format = 'NEWLINE_DELIMITED_JSON',
    uris   = [
      'gs://smartbetting-landingzone/nba/game_player_stats/2023/*.json',
      'gs://smartbetting-landingzone/nba/game_player_stats/2024/*.json',
      'gs://smartbetting-landingzone/nba/game_player_stats/2025/*.json'
    ]
  );

-- Passo 2: Criar tabela histórica permanente
CREATE OR REPLACE TABLE `smartbetting-dados.nba.ft_game_player_stats_historical`
PARTITION BY game_date
CLUSTER BY season, player_id
AS

WITH source_data AS (
    SELECT
        season,
        stat
    FROM `smartbetting-dados.nba.raw_game_player_stats_all_seasons`,
    UNNEST(stats) AS stat
),

cleaned AS (
    SELECT
        CAST(stat.player.id AS INT64)           AS player_id,
        CAST(stat.team.id AS INT64)             AS team_id,
        CAST(stat.game.id AS INT64)             AS game_id,
        CAST(stat.game.date AS DATE)            AS game_date,
        CAST(season AS INT64)                   AS season,
        LOWER(COALESCE(stat.season_type, 'regular')) AS season_type,

        -- Scores
        CAST(stat.game.home_team_score AS INT64)    AS home_team_score,
        CAST(stat.game.home_team_id AS INT64)       AS home_team_id,
        CAST(stat.game.visitor_team_score AS INT64) AS visitor_team_score,
        CAST(stat.game.visitor_team_id AS INT64)    AS visitor_team_id,
        CASE
            WHEN CAST(stat.game.home_team_score AS INT64) > CAST(stat.game.visitor_team_score AS INT64)
                THEN CAST(stat.game.home_team_id AS INT64)
            WHEN CAST(stat.game.visitor_team_score AS INT64) > CAST(stat.game.home_team_score AS INT64)
                THEN CAST(stat.game.visitor_team_id AS INT64)
        END AS winner_team_id,

        -- Minutos
        SAFE_CAST(stat.min AS INT64)                AS minutes,

        -- Stats individuais
        SAFE_CAST(stat.pts AS INT64)                AS points,
        SAFE_CAST(stat.reb AS INT64)                AS rebounds,
        SAFE_CAST(stat.ast AS INT64)                AS assists,
        SAFE_CAST(stat.fg3m AS INT64)               AS threes,
        SAFE_CAST(stat.oreb AS INT64)               AS offensive_rebounds,
        SAFE_CAST(stat.dreb AS INT64)               AS defensive_rebounds,
        SAFE_CAST(stat.stl AS INT64)                AS steals,
        SAFE_CAST(stat.blk AS INT64)                AS blocks,
        SAFE_CAST(stat.turnover AS INT64)           AS turnovers,
        SAFE_CAST(stat.fg_pct AS FLOAT64)           AS field_goal_percentage,
        SAFE_CAST(stat.ft_pct AS FLOAT64)           AS free_throw_percentage,
        SAFE_CAST(stat.plus_minus AS INT64)         AS plus_minus,

        -- Combos
        SAFE_CAST(stat.pts AS INT64) + SAFE_CAST(stat.reb AS INT64)
            AS points_rebounds,
        SAFE_CAST(stat.pts AS INT64) + SAFE_CAST(stat.ast AS INT64)
            AS points_assists,
        SAFE_CAST(stat.reb AS INT64) + SAFE_CAST(stat.ast AS INT64)
            AS rebounds_assists,
        SAFE_CAST(stat.pts AS INT64) + SAFE_CAST(stat.reb AS INT64) + SAFE_CAST(stat.ast AS INT64)
            AS points_rebounds_assists,
        SAFE_CAST(stat.blk AS INT64) + SAFE_CAST(stat.stl AS INT64)
            AS blocks_steals,

        -- Flags
        CASE
            WHEN (
                CAST(SAFE_CAST(stat.pts AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.reb AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.ast AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.stl AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.blk AS INT64) > 10 AS INT64)
            ) >= 3 THEN TRUE ELSE FALSE
        END AS triple_double,
        CASE
            WHEN (
                CAST(SAFE_CAST(stat.pts AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.reb AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.ast AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.stl AS INT64) > 10 AS INT64)
                + CAST(SAFE_CAST(stat.blk AS INT64) > 10 AS INT64)
            ) >= 2 THEN TRUE ELSE FALSE
        END AS double_double

    FROM source_data
    WHERE stat.min IS NOT NULL
      AND SAFE_CAST(stat.min AS INT64) > 0
)

SELECT * FROM cleaned;
