

WITH lados AS (
    -- `mandante`/`visitante` seguem o jogo, e não o lado da linha: a partida sai impressa na
    -- ordem em que foi disputada, não na ordem em que o UNION a produziu.
    SELECT fixture_id, competition, competition_id, kickoff_utc, status_short,
           home_team_id AS team_id, home_team_name AS team_name,
           home_team_name AS mandante, away_team_name AS visitante
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    UNION ALL
    SELECT fixture_id, competition, competition_id, kickoff_utc, status_short,
           away_team_id, away_team_name,
           home_team_name, away_team_name
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

ancoras AS (
    SELECT * FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short = 'FT'
)

SELECT
    a.competition                                        AS competicao_da_ancora,
    a.fixture_id                                         AS ancora_fixture_id,
    a.mandante || ' × ' || a.visitante                   AS ancora_partida,
    a.team_name                                          AS time,
    FORMAT_TIMESTAMP('%F %H:%M', a.kickoff_utc)          AS ancora_kickoff_utc,
    FORMAT_TIMESTAMP('%F %H:%M',
        TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY))  AS fronteira_utc,

    h.fixture_id                                         AS partida_fixture_id,
    h.competition                                        AS partida_competicao,
    h.mandante || ' × ' || h.visitante                   AS partida,
    FORMAT_TIMESTAMP('%F %H:%M', h.kickoff_utc)          AS partida_kickoff_utc,

    -- De quanto ela está dentro (positivo) ou fora (negativo) da fronteira por instante.
    TIMESTAMP_DIFF(h.kickoff_utc,
        TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY), MINUTE) AS distancia_da_fronteira_min,

    -- Qual régua conta esta partida. As duas colunas discordam por construção: só aparecem aqui
    -- as linhas em que discordam.
    h.kickoff_utc >= TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY)          AS conta_por_instante,
    DATE(h.kickoff_utc) >  DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY)   AS conta_por_data_estrita

FROM ancoras a
JOIN lados h
    ON  h.team_id        = a.team_id
    AND h.kickoff_utc    < a.kickoff_utc
    AND h.status_short   = 'FT'
WHERE (h.kickoff_utc >= TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY))
   != (DATE(h.kickoff_utc) > DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY))
ORDER BY a.kickoff_utc, h.kickoff_utc