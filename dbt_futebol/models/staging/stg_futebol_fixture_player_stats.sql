{{ config(
    description='Flatten do raw_futebol_fixture_player_stats. 1 linha por (fixture_id, player_id). statistics (struct único, statistics[0] da API) achatado em colunas tipadas; rating/passes_accuracy via SAFE_CAST (a API manda string); penalty_committed corrige a grafia errada da API (penalty.commited, 1 "t"). Sem pivot/UNNEST (a ordem dos jogadores não importa). fact_fixture_player_stats faz o latest-wins por (fixture_id, player_id).'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_fixture_player_stats') }}
)

SELECT
    src.fixture_id,
    src.loaded_at,

    src.team.id   AS team_id,
    src.team.name AS team_name,

    src.player.id    AS player_id,
    src.player.name  AS player_name,
    src.player.photo AS player_photo,

    -- games (rating vem string "6.3" — cast aqui)
    src.statistics.games.minutes    AS minutes,
    src.statistics.games.number     AS shirt_number,
    src.statistics.games.position   AS position,
    SAFE_CAST(src.statistics.games.rating AS FLOAT64) AS rating,
    src.statistics.games.captain    AS is_captain,
    src.statistics.games.substitute AS is_substitute,

    -- finalização / gols
    src.statistics.offsides       AS offsides,
    src.statistics.shots.total    AS shots_total,
    src.statistics.shots.`on`     AS shots_on,          -- `on` escapado (keyword SQL)
    src.statistics.goals.total    AS goals_total,
    src.statistics.goals.conceded AS goals_conceded,
    src.statistics.goals.assists  AS assists,
    src.statistics.goals.saves    AS saves,

    -- passes (accuracy vem string — cast aqui)
    src.statistics.passes.total AS passes_total,
    src.statistics.passes.key   AS passes_key,
    SAFE_CAST(src.statistics.passes.accuracy AS INT64) AS passes_accuracy,

    -- defesa / duelos / dribles
    src.statistics.tackles.total         AS tackles_total,
    src.statistics.tackles.blocks        AS tackles_blocks,
    src.statistics.tackles.interceptions AS interceptions,
    src.statistics.duels.total AS duels_total,
    src.statistics.duels.won   AS duels_won,
    src.statistics.dribbles.attempts AS dribbles_attempts,
    src.statistics.dribbles.success  AS dribbles_success,
    src.statistics.dribbles.past     AS dribbles_past,

    -- disciplina
    src.statistics.fouls.drawn     AS fouls_drawn,
    src.statistics.fouls.committed AS fouls_committed,   -- grafia certa (2 "t")
    src.statistics.cards.yellow AS yellow_cards,
    src.statistics.cards.red    AS red_cards,

    -- pênaltis (penalty.commited tem grafia ERRADA da API → alias correto)
    src.statistics.penalty.won      AS penalty_won,
    src.statistics.penalty.commited AS penalty_committed,
    src.statistics.penalty.scored   AS penalty_scored,
    src.statistics.penalty.missed   AS penalty_missed,
    src.statistics.penalty.saved    AS penalty_saved
FROM src
