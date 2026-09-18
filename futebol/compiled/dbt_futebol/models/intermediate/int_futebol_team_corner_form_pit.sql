

WITH fixtures AS (
    SELECT
        fixture_id, competition_id, season, kickoff_utc,
        home_team_id, away_team_id,
        status_short, score_fulltime_home, score_fulltime_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- Grão de saída: os dois lados de cada jogo, inclusive jogos futuros — mesmo padrão de
-- int_futebol_team_form_pit.
targets AS (
    SELECT fixture_id, competition_id, season, kickoff_utc, home_team_id AS team_id, 'home' AS team_side
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc, away_team_id, 'away'
    FROM fixtures
),

-- O par do jogo: os escanteios SOFRIDOS por um time são os escanteios FEITOS pelo
-- adversário na MESMA partida — self-join por fixture_id, team_id diferente. Todo jogo
-- com estatística coletada tem exatamente 2 linhas em fact_fixture_stats (medido em
-- produção: zero exceções), então este join não duplica nem descarta linha.
corner_log AS (
    SELECT
        f.fixture_id,
        a.team_id,
        a.team_side,
        f.kickoff_utc,
        a.corner_kicks    AS corners_for,
        b.corner_kicks    AS corners_against,
        a.ball_possession AS possession,
        a.expected_goals  AS xg,
        a.shots_insidebox AS shots_insidebox,
        a.total_shots      AS total_shots,
        a.shots_outsidebox AS shots_outsidebox,
        a.blocked_shots    AS blocked_shots,
        a.goalkeeper_saves AS goalkeeper_saves,
        a.fouls            AS fouls
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats` a
    JOIN `smartbetting-dados`.`futebol`.`fact_fixture_stats` b
        ON  b.fixture_id = a.fixture_id
        AND b.team_id   <> a.team_id
    JOIN fixtures f ON f.fixture_id = a.fixture_id
    WHERE 
    f.status_short IN ('FT', 'AET', 'PEN')
      AND f.score_fulltime_home IS NOT NULL
      AND f.score_fulltime_away IS NOT NULL
),

-- JANELA DE 10 — qualquer competição. `played_total_disponivel` usa COUNT(l.kickoff_utc),
-- não COUNT(*): o LEFT JOIN sem correspondência devolve uma linha com kickoff NULL (o time
-- sem passado), e COUNT(*) contaria essa linha fantasma como 1 jogo. COUNT(l.kickoff_utc)
-- ignora o NULL e mantém 0, mesma convenção de int_futebol_team_form_pit.
pares10 AS (
    SELECT
        t.fixture_id,
        t.team_id,
        l.kickoff_utc,
        l.corners_for,
        l.corners_against,
        l.possession,
        l.xg,
        l.shots_insidebox,
        l.total_shots,
        l.shots_outsidebox,
        l.blocked_shots,
        l.goalkeeper_saves,
        l.fouls,
        COUNT(l.kickoff_utc) OVER (PARTITION BY t.fixture_id, t.team_id) AS played_total_disponivel
    FROM targets t
    LEFT JOIN corner_log l
        ON  l.team_id     = t.team_id
        AND l.kickoff_utc < t.kickoff_utc
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY t.fixture_id, t.team_id ORDER BY l.kickoff_utc DESC
    ) <= 10
),

pit10 AS (
    SELECT
        fixture_id,
        team_id,
        COUNT(kickoff_utc)            AS played_total,
        MAX(played_total_disponivel)  AS played_total_disponivel,
        SAFE_DIVIDE(SUM(corners_for),     COUNTIF(corners_for     IS NOT NULL)) AS corners_for_avg10,
        SAFE_DIVIDE(SUM(corners_against), COUNTIF(corners_against IS NOT NULL)) AS corners_against_avg10,
        SAFE_DIVIDE(SUM(possession),      COUNTIF(possession      IS NOT NULL)) AS possession_avg10,
        SAFE_DIVIDE(SUM(xg),              COUNTIF(xg              IS NOT NULL)) AS xg_avg10,
        SAFE_DIVIDE(SUM(shots_insidebox), COUNTIF(shots_insidebox IS NOT NULL)) AS shots_insidebox_avg10,
        SAFE_DIVIDE(SUM(total_shots),      COUNTIF(total_shots      IS NOT NULL)) AS total_shots_avg10,
        SAFE_DIVIDE(SUM(shots_outsidebox), COUNTIF(shots_outsidebox IS NOT NULL)) AS shots_outsidebox_avg10,
        SAFE_DIVIDE(SUM(blocked_shots),    COUNTIF(blocked_shots    IS NOT NULL)) AS blocked_shots_avg10,
        SAFE_DIVIDE(SUM(goalkeeper_saves), COUNTIF(goalkeeper_saves IS NOT NULL)) AS goalkeeper_saves_avg10,
        SAFE_DIVIDE(SUM(fouls),            COUNTIF(fouls            IS NOT NULL)) AS fouls_avg10
    FROM pares10
    GROUP BY fixture_id, team_id
),

-- JANELA DE MANDO — os 5 jogos anteriores do time no MESMO mando (`l.team_side = t.team_side`
-- filtra quem concorre pela vaga antes do ROW_NUMBER; um visitante nunca compete pelos 5
-- jogos mais recentes de um mandante).
pares_mando5 AS (
    SELECT
        t.fixture_id,
        t.team_id,
        l.kickoff_utc,
        l.corners_for,
        l.corners_against,
        l.possession,
        l.xg,
        l.shots_insidebox,
        l.total_shots,
        l.shots_outsidebox,
        l.blocked_shots,
        l.goalkeeper_saves,
        l.fouls
    FROM targets t
    LEFT JOIN corner_log l
        ON  l.team_id     = t.team_id
        AND l.team_side   = t.team_side
        AND l.kickoff_utc < t.kickoff_utc
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY t.fixture_id, t.team_id ORDER BY l.kickoff_utc DESC
    ) <= 5
),

mando5 AS (
    SELECT
        fixture_id,
        team_id,
        COUNT(kickoff_utc) AS played_mando5,
        SAFE_DIVIDE(SUM(corners_for),     COUNTIF(corners_for     IS NOT NULL)) AS corners_for_avg_mando5,
        SAFE_DIVIDE(SUM(corners_against), COUNTIF(corners_against IS NOT NULL)) AS corners_against_avg_mando5,
        SAFE_DIVIDE(SUM(possession),      COUNTIF(possession      IS NOT NULL)) AS possession_avg_mando5,
        SAFE_DIVIDE(SUM(xg),              COUNTIF(xg              IS NOT NULL)) AS xg_avg_mando5,
        SAFE_DIVIDE(SUM(shots_insidebox), COUNTIF(shots_insidebox IS NOT NULL)) AS shots_insidebox_avg_mando5,
        SAFE_DIVIDE(SUM(total_shots),      COUNTIF(total_shots      IS NOT NULL)) AS total_shots_avg_mando5,
        SAFE_DIVIDE(SUM(shots_outsidebox), COUNTIF(shots_outsidebox IS NOT NULL)) AS shots_outsidebox_avg_mando5,
        SAFE_DIVIDE(SUM(blocked_shots),    COUNTIF(blocked_shots    IS NOT NULL)) AS blocked_shots_avg_mando5,
        SAFE_DIVIDE(SUM(goalkeeper_saves), COUNTIF(goalkeeper_saves IS NOT NULL)) AS goalkeeper_saves_avg_mando5,
        SAFE_DIVIDE(SUM(fouls),            COUNTIF(fouls            IS NOT NULL)) AS fouls_avg_mando5
    FROM pares_mando5
    GROUP BY fixture_id, team_id
)

SELECT
    t.fixture_id,
    t.team_id,
    t.team_side,
    t.competition_id,
    t.season,
    t.kickoff_utc,

    p10.played_total,
    p10.played_total_disponivel,
    IF(p10.played_total < 10, NULL, p10.corners_for_avg10)     AS corners_for_avg10,
    IF(p10.played_total < 10, NULL, p10.corners_against_avg10) AS corners_against_avg10,
    IF(p10.played_total < 10, NULL, p10.possession_avg10)      AS possession_avg10,
    IF(p10.played_total < 10, NULL, p10.xg_avg10)              AS xg_avg10,
    IF(p10.played_total < 10, NULL, p10.shots_insidebox_avg10) AS shots_insidebox_avg10,
    IF(p10.played_total < 10, NULL, p10.total_shots_avg10)      AS total_shots_avg10,
    IF(p10.played_total < 10, NULL, p10.shots_outsidebox_avg10) AS shots_outsidebox_avg10,
    IF(p10.played_total < 10, NULL, p10.blocked_shots_avg10)    AS blocked_shots_avg10,
    IF(p10.played_total < 10, NULL, p10.goalkeeper_saves_avg10) AS goalkeeper_saves_avg10,
    IF(p10.played_total < 10, NULL, p10.fouls_avg10)            AS fouls_avg10,

    m5.played_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.corners_for_avg_mando5)     AS corners_for_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.corners_against_avg_mando5) AS corners_against_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.possession_avg_mando5)      AS possession_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.xg_avg_mando5)              AS xg_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.shots_insidebox_avg_mando5) AS shots_insidebox_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.total_shots_avg_mando5)      AS total_shots_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.shots_outsidebox_avg_mando5) AS shots_outsidebox_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.blocked_shots_avg_mando5)    AS blocked_shots_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.goalkeeper_saves_avg_mando5) AS goalkeeper_saves_avg_mando5,
    IF(m5.played_mando5 < 5, NULL, m5.fouls_avg_mando5)            AS fouls_avg_mando5,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM targets t
JOIN pit10 p10 ON p10.fixture_id = t.fixture_id AND p10.team_id = t.team_id
JOIN mando5 m5 ON m5.fixture_id = t.fixture_id AND m5.team_id = t.team_id