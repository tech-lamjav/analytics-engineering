{{ config(
    description='Staging for NBA player advanced/tracking stats per game from Balldontlie /nba/v2/stats/advanced. One row per player per game with passing, playmaking, hustle and rating fields.'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_game_player_advanced_stats') }}
    WHERE season = 2025
),

unnested AS (
    SELECT stat
    FROM source_data,
    UNNEST(stats) AS stat
),

cleaned_data AS (
    SELECT
        CAST(stat.player.id AS INT64) AS player_id,
        CAST(stat.team.id AS INT64) AS team_id,
        CAST(stat.game.id AS INT64) AS game_id,
        stat.game.date AS game_date,
        CAST(stat.game.season AS INT64) AS season,
        stat.season_type,

        -- Playmaking / passing
        CAST(stat.passes AS INT64) AS passes,
        CAST(stat.secondary_assists AS INT64) AS secondary_assists,
        CAST(stat.free_throw_assists AS INT64) AS free_throw_assists,
        CAST(stat.screen_assists AS INT64) AS screen_assists,
        CAST(stat.screen_assist_points AS INT64) AS screen_assist_points,
        CAST(stat.assist_percentage AS FLOAT64) AS assist_percentage,
        CAST(stat.assist_ratio AS FLOAT64) AS assist_ratio,
        CAST(stat.assist_to_turnover AS FLOAT64) AS assist_to_turnover,
        CAST(stat.turnover_ratio AS FLOAT64) AS turnover_ratio,
        CAST(stat.usage_percentage AS FLOAT64) AS usage_percentage,

        -- Volume / tempo
        CAST(stat.touches AS INT64) AS touches,
        CAST(stat.possessions AS INT64) AS possessions,
        CAST(stat.partial_possessions AS FLOAT64) AS partial_possessions,
        CAST(stat.speed AS FLOAT64) AS speed,
        CAST(stat.distance AS FLOAT64) AS distance,

        -- Eficiência / ratings (úteis para outros marts)
        CAST(stat.pie AS FLOAT64) AS pie,
        CAST(stat.offensive_rating AS FLOAT64) AS offensive_rating,
        CAST(stat.defensive_rating AS FLOAT64) AS defensive_rating,
        CAST(stat.net_rating AS FLOAT64) AS net_rating,
        CAST(stat.true_shooting_percentage AS FLOAT64) AS true_shooting_percentage,
        CAST(stat.effective_field_goal_percentage AS FLOAT64) AS effective_field_goal_percentage,

        -- Hustle / defesa (reuso futuro)
        CAST(stat.deflections AS INT64) AS deflections,
        CAST(stat.contested_shots AS INT64) AS contested_shots,
        CAST(stat.box_outs AS INT64) AS box_outs,
        CAST(stat.charges_drawn AS INT64) AS charges_drawn,
        CAST(stat.points_paint AS INT64) AS points_paint,
        CAST(stat.points_fast_break AS INT64) AS points_fast_break,
        CAST(stat.points_second_chance AS INT64) AS points_second_chance,
        CAST(stat.points_off_turnovers AS INT64) AS points_off_turnovers,

        -- Período (0 = jogo completo, 1-4 = quartos)
        CAST(stat.period AS INT64) AS period
    FROM unnested
)

SELECT * FROM cleaned_data
