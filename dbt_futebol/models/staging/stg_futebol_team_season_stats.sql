{{ config(
    description='Flatten do raw_futebol_team_season_stats. 1 linha por (team_id, requested_league_id, requested_season). Objeto curado do /teams/statistics achatado em colunas tipadas; médias (goals_*_avg_*) e percentuais de pênalti via SAFE_CAST (a API manda STRING; "%" removido). `for` escapado com crases (keyword SQL). fact_team_season_stats deriva competition e dedup por (team_id, liga, season).'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_team_season_stats') }}
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.snapshot_date,
    src.loaded_at,

    src.team.id   AS team_id,
    src.team.name AS team_name,
    src.form,

    -- fixtures (jogos / vitórias / empates / derrotas)
    src.fixtures.played.home  AS played_home,
    src.fixtures.played.away  AS played_away,
    src.fixtures.played.total AS played_total,
    src.fixtures.wins.home    AS wins_home,
    src.fixtures.wins.away    AS wins_away,
    src.fixtures.wins.total   AS wins_total,
    src.fixtures.draws.home   AS draws_home,
    src.fixtures.draws.away   AS draws_away,
    src.fixtures.draws.total  AS draws_total,
    src.fixtures.loses.home   AS loses_home,
    src.fixtures.loses.away   AS loses_away,
    src.fixtures.loses.total  AS loses_total,

    -- gols marcados (total + média; `for` escapado, keyword SQL; média vem STRING)
    src.goals.`for`.total.home    AS goals_for_home,
    src.goals.`for`.total.away    AS goals_for_away,
    src.goals.`for`.total.total   AS goals_for_total,
    SAFE_CAST(src.goals.`for`.average.home  AS FLOAT64) AS goals_for_avg_home,
    SAFE_CAST(src.goals.`for`.average.away  AS FLOAT64) AS goals_for_avg_away,
    SAFE_CAST(src.goals.`for`.average.total AS FLOAT64) AS goals_for_avg_total,

    -- gols sofridos (total + média)
    src.goals.against.total.home  AS goals_against_home,
    src.goals.against.total.away  AS goals_against_away,
    src.goals.against.total.total AS goals_against_total,
    SAFE_CAST(src.goals.against.average.home  AS FLOAT64) AS goals_against_avg_home,
    SAFE_CAST(src.goals.against.average.away  AS FLOAT64) AS goals_against_avg_away,
    SAFE_CAST(src.goals.against.average.total AS FLOAT64) AS goals_against_avg_total,

    -- defesa / ataque agregados
    src.clean_sheet.home      AS clean_sheet_home,
    src.clean_sheet.away      AS clean_sheet_away,
    src.clean_sheet.total     AS clean_sheet_total,
    src.failed_to_score.home  AS failed_to_score_home,
    src.failed_to_score.away  AS failed_to_score_away,
    src.failed_to_score.total AS failed_to_score_total,

    -- maiores marcas (streaks INT; placares STRING '3-0')
    src.biggest.streak.wins   AS biggest_streak_wins,
    src.biggest.streak.draws  AS biggest_streak_draws,
    src.biggest.streak.loses  AS biggest_streak_loses,
    src.biggest.wins.home     AS biggest_win_home,
    src.biggest.wins.away     AS biggest_win_away,
    src.biggest.loses.home    AS biggest_lose_home,
    src.biggest.loses.away    AS biggest_lose_away,
    src.biggest.goals.`for`.home     AS biggest_goals_for_home,
    src.biggest.goals.`for`.away     AS biggest_goals_for_away,
    src.biggest.goals.against.home   AS biggest_goals_against_home,
    src.biggest.goals.against.away   AS biggest_goals_against_away,

    -- pênaltis (percentual vem STRING '100%' — strip + cast)
    src.penalty.scored.total AS penalty_scored_total,
    SAFE_CAST(REPLACE(src.penalty.scored.percentage, '%', '') AS FLOAT64) AS penalty_scored_pct,
    src.penalty.missed.total AS penalty_missed_total,
    SAFE_CAST(REPLACE(src.penalty.missed.percentage, '%', '') AS FLOAT64) AS penalty_missed_pct,
    src.penalty.total        AS penalty_total
FROM src
