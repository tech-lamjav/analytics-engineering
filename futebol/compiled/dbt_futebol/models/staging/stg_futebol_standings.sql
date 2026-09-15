

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_standings`
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.snapshot_date,
    src.loaded_at,

    src.team.id   AS team_id,
    src.team.name AS team_name,
    src.team.logo AS team_logo,

    src.rank,
    src.points,
    src.goalsDiff AS goals_diff,
    src.`group`   AS group_name,
    src.form,
    src.status      AS rank_status,
    src.description AS rank_description,
    src.update      AS standings_updated_at,

    -- campanha geral (KEYWORDS SQL escapadas com crases)
    src.`all`.played        AS played_total,
    src.`all`.win           AS wins_total,
    src.`all`.draw          AS draws_total,
    src.`all`.lose          AS loses_total,
    src.`all`.goals.`for`   AS goals_for_total,
    src.`all`.goals.against AS goals_against_total,

    -- campanha como mandante
    src.home.played        AS played_home,
    src.home.win           AS wins_home,
    src.home.draw          AS draws_home,
    src.home.lose          AS loses_home,
    src.home.goals.`for`   AS goals_for_home,
    src.home.goals.against AS goals_against_home,

    -- campanha como visitante
    src.away.played        AS played_away,
    src.away.win           AS wins_away,
    src.away.draw          AS draws_away,
    src.away.lose          AS loses_away,
    src.away.goals.`for`   AS goals_for_away,
    src.away.goals.against AS goals_against_away
FROM src
-- Defensivo: ignora eventual linha metadata-only (arquivo subido sem standings)
WHERE src.rank IS NOT NULL