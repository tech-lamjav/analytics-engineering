

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc,
        status_short, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- Grão de saída: os dois lados de cada jogo (inclusive jogos futuros).
targets AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           home_team_id AS team_id
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           away_team_id
    FROM fixtures
),

-- Jogos FINALIZADOS viram 1 linha por (time, jogo), com o eixo casa/fora. É a única fonte de
-- performance daqui p/ baixo — mesmo idioma das CTEs last5/margin_stats/team_hist que já existem.
team_log AS (
    SELECT competition_id, season, kickoff_utc, home_team_id AS team_id,
           TRUE AS is_home, goals_home AS gf, goals_away AS ga
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
    UNION ALL
    SELECT competition_id, season, kickoff_utc, away_team_id,
           FALSE, goals_away, goals_home
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),

-- Universo de times por (liga, season) — tirado de fixtures, não de standings, p/ a Copa do
-- Brasil (sem tabela) também ter n_teams.
league_teams AS (
    SELECT DISTINCT competition_id, season, team_id
    FROM targets
),
league_size AS (
    SELECT competition_id, season, COUNT(*) AS n_teams
    FROM league_teams
    GROUP BY competition_id, season
),

-- Grupo de cada time. É estrutura de chaveamento (o sorteio), conhecida antes dos jogos —
-- entra só p/ o rank PIT ser calculado no mesmo recorte que o rank da API. Dedup igual ao
-- standings_latest que estava nos modelos: prefere o grupo principal ao "third-placed".
team_group AS (
    SELECT league_id AS competition_id, season, team_id, group_name
    FROM `smartbetting-dados`.`futebol`.`fact_standings_snapshot`
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END,
                 snapshot_date DESC
    ) = 1
),

-- Cada fixture é uma ÂNCORA DE TEMPO. Cruzada com TODOS os times da liga porque o rank exige a
-- tabela inteira naquele instante, não só os dois times do jogo (o filtro p/ os dois vem no fim).
anchors AS (
    SELECT fixture_id, competition_id, season, kickoff_utc FROM fixtures
),

pit AS (
    SELECT
        a.fixture_id,
        lt.team_id,
        a.competition_id,
        a.season,

        -- jogos / resultados
        COUNTIF(l.is_home)                          AS played_home,
        COUNTIF(NOT l.is_home)                      AS played_away,
        COUNT(l.team_id)                            AS played_total,
        COUNTIF(l.is_home       AND l.gf > l.ga)    AS wins_home,
        COUNTIF(l.is_home       AND l.gf = l.ga)    AS draws_home,
        COUNTIF(NOT l.is_home   AND l.gf > l.ga)    AS wins_away,
        COUNTIF(NOT l.is_home   AND l.gf = l.ga)    AS draws_away,
        COUNTIF(l.gf > l.ga)                        AS wins_total,
        COUNTIF(l.gf = l.ga)                        AS draws_total,

        -- gols marcados / sofridos (médias por venue e no total)
        SAFE_DIVIDE(SUM(IF(l.is_home,     l.gf, 0)), COUNTIF(l.is_home))     AS goals_for_avg_home,
        SAFE_DIVIDE(SUM(IF(NOT l.is_home, l.gf, 0)), COUNTIF(NOT l.is_home)) AS goals_for_avg_away,
        SAFE_DIVIDE(SUM(l.gf),                       COUNT(l.team_id))       AS goals_for_avg_total,
        SAFE_DIVIDE(SUM(IF(l.is_home,     l.ga, 0)), COUNTIF(l.is_home))     AS goals_against_avg_home,
        SAFE_DIVIDE(SUM(IF(NOT l.is_home, l.ga, 0)), COUNTIF(NOT l.is_home)) AS goals_against_avg_away,
        SAFE_DIVIDE(SUM(l.ga),                       COUNT(l.team_id))       AS goals_against_avg_total,

        -- defesa / ataque agregados
        COUNTIF(l.ga = 0)                           AS clean_sheet_total,
        COUNTIF(l.gf = 0)                           AS failed_to_score_total,

        -- insumos da tabela do campeonato
        COUNTIF(l.gf > l.ga) * 3 + COUNTIF(l.gf = l.ga)  AS points,
        COALESCE(SUM(l.gf), 0)                           AS goals_for_total,
        COALESCE(SUM(l.gf) - SUM(l.ga), 0)               AS goal_diff,

        -- forma: os últimos 5 resultados ANTES do jogo (substitui o parse de standings.form)
        ARRAY_AGG(
            CASE WHEN l.gf > l.ga THEN 'W'
                 WHEN l.gf = l.ga THEN 'D'
                 WHEN l.gf < l.ga THEN 'L' END
            IGNORE NULLS ORDER BY l.kickoff_utc DESC LIMIT 5
        ) AS last5_desc
    FROM anchors a
    JOIN league_teams lt
        ON  lt.competition_id = a.competition_id
        AND lt.season         = a.season
    LEFT JOIN team_log l
        ON  l.team_id        = lt.team_id
        AND l.competition_id = a.competition_id
        AND l.season         = a.season
        AND l.kickoff_utc    < a.kickoff_utc
    GROUP BY a.fixture_id, lt.team_id, a.competition_id, a.season
),

-- Tabela do campeonato no instante do jogo. Critério de desempate = pontos > vitórias > saldo >
-- gols pró (o do Brasileirão), + team_id p/ ser determinístico. ROW_NUMBER e não RANK porque o
-- rank da API é estrito (não repete posição), e o modelo compara diferenças de rank.
-- rank NULL quando o time ainda não jogou na temporada: antes da rodada 1 a tabela não existe e
-- todo mundo empataria em 0 -> `s_rank <= 6` do sem_rodizio dispararia p/ a liga inteira.
ranked AS (
    SELECT
        p.*,
        tg.group_name,
        IF(tg.group_name IS NULL OR p.played_total = 0, NULL,
           ROW_NUMBER() OVER (
               PARTITION BY p.fixture_id, tg.group_name
               ORDER BY p.points DESC, p.wins_total DESC, p.goal_diff DESC,
                        p.goals_for_total DESC, p.team_id
           )
        ) AS rank
    FROM pit p
    LEFT JOIN team_group tg
        ON  tg.competition_id = p.competition_id
        AND tg.season         = p.season
        AND tg.team_id        = p.team_id
)

SELECT
    t.fixture_id,
    t.team_id,
    t.competition,
    t.competition_id,
    t.season,
    t.kickoff_utc,

    -- jogos / resultados (todos PIT)
    r.played_home,
    r.played_away,
    r.played_total,
    r.wins_home,
    r.draws_home,
    r.wins_away,
    r.draws_away,
    r.wins_total,
    r.draws_total,

    -- gols
    r.goals_for_avg_home,
    r.goals_for_avg_away,
    r.goals_for_avg_total,
    r.goals_against_avg_home,
    r.goals_against_avg_away,
    r.goals_against_avg_total,
    r.clean_sheet_total,
    r.failed_to_score_total,

    -- tabela do campeonato no instante do jogo
    r.rank,
    r.points,
    r.goal_diff,
    SAFE_DIVIDE(r.points, r.played_total) AS ppg,
    ls.n_teams,
    r.group_name,

    -- forma (últimos 5 antes do jogo). form_last5 sai do mais ANTIGO p/ o mais RECENTE, igual à
    -- convenção do campo form da API (que os modelos liam com RIGHT(form, 5)).
    (SELECT COUNT(*) FROM UNNEST(r.last5_desc) x WHERE x = 'W') AS n_wins_last5,
    ARRAY_LENGTH(COALESCE(r.last5_desc, []))                    AS n_games_last5,
    ARRAY_TO_STRING(ARRAY_REVERSE(COALESCE(r.last5_desc, [])), '') AS form_last5,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM targets t
JOIN ranked r
    ON  r.fixture_id = t.fixture_id
    AND r.team_id    = t.team_id
LEFT JOIN league_size ls
    ON  ls.competition_id = t.competition_id
    AND ls.season         = t.season