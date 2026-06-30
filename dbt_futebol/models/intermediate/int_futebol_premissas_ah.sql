{{ config(
    materialized='table',
    description='S3 do Motor de Score — premissas de contexto do mercado HANDICAP ASIATICO (market_id 4). 2 linhas por (fixture, line_value): outcome_side Home e Away. Convenção dos dados (API-Football, confirmada 2026-06-24): line_value é o handicap na ÓTICA DO MANDANTE e é o MESMO p/ os dois lados — "Home -1.5" e "Away -1.5" são o PAR complementar (de-vig soma ~1.03, pin_n_outcomes=2). Logo o handicap NA ÓTICA DO LADO = IF(side=Home, line_value, -line_value): side_handicap<0 => FAVORITO (dá handicap), >0 => AZARÃO (recebe), =0 => pick (nenhuma premissa dispara). Favorito: 5 premissas (Σ40, §12.3); Azarão: 3 (Σ30). Penalidade específica: handicap_alto (-12, |line_value|>=2.5). Degradação graciosa: dado ausente -> premissa FALSE. evidencias[]/avisos[] = bullets pro front. Gate/edge/Score saem no mart fact_value_opportunities (gate de completude Pinnacle = par >=2, igual O/U).
    ⚠️ Reconciliação §12.3: o bloco "Azarão" do playbook mistura rótulos S/O (ex.: "favorito_irregular | S venceu por 2+..."); aqui as premissas seguem o NOME/INTENÇÃO: raramente_perde_por_2 e defesa_fora_solida medem o AZARÃO (S); favorito_irregular mede o FAVORITO (O). Ao calibrar, alinhar o .md a esta leitura.'
) }}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

-- Universo de linhas: canônicas (toda fixture, p/ validar mesmo sem odds na pausa FIFA) +
-- linhas reais das odds (market_id=4). Canônicas cobrem favorito (-) e azarão (+) dos dois lados.
canonical_lines AS (
    SELECT f.fixture_id, l AS line_value
    FROM fixtures f, UNNEST([-1.5, -0.5, 0.5, 1.5]) AS l
),
market_lines AS (
    SELECT DISTINCT fixture_id, line_value
    FROM {{ ref('fact_odds_snapshot') }}
    WHERE market_id = 4 AND line_value IS NOT NULL
),
lines AS (
    SELECT fixture_id, line_value FROM canonical_lines
    UNION DISTINCT
    SELECT fixture_id, line_value FROM market_lines
),

-- 2 outcomes (Home/Away) por (fixture, linha). Resolve S (lado apostado), O (adversário),
-- mando e o handicap na ótica do lado (sinal define favorito/azarão).
outcomes AS (
    SELECT
        l.fixture_id, f.competition, f.competition_id, f.season, f.kickoff_utc,
        l.line_value,
        side AS outcome,
        (side = 'Home')                                       AS s_is_home,
        IF(side = 'Home', f.home_team_id, f.away_team_id)     AS s_team_id,
        IF(side = 'Home', f.away_team_id, f.home_team_id)     AS o_team_id,
        IF(side = 'Home', l.line_value, -l.line_value)        AS side_handicap
    FROM lines l
    JOIN fixtures f USING (fixture_id)
    CROSS JOIN UNNEST(['Home', 'Away']) AS side
),

tss AS (
    SELECT
        team_id, season, competition_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        wins_home, draws_home, played_home
    FROM {{ ref('fact_team_season_stats') }}
),

-- 1 linha por (liga, season, time): snapshot mais recente; evita a linha duplicada
-- "third-placed" da Copa preferindo o grupo principal (mesmo padrão do 1X2).
standings_latest AS (
    SELECT league_id, season, team_id, rank, points, played_total
    FROM {{ ref('fact_standings_snapshot') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY snapshot_date DESC,
                 CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END
    ) = 1
),
-- Nº de times por (liga, season) p/ o proxy de motivação (sem_rodizio).
league_size AS (
    SELECT league_id, season, COUNT(*) AS n_teams
    FROM standings_latest
    GROUP BY league_id, season
),

-- Margem (gols pró − contra) por time em cada jogo FINALIZADO; vira a base de
-- "perde/vence por 2+". Reusa o padrão de fixtures finalizadas do O/U.
finished AS (
    SELECT competition_id, kickoff_utc, home_team_id, away_team_id, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),
team_results AS (
    SELECT home_team_id AS team_id, competition_id, kickoff_utc, goals_home - goals_away AS margin FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, kickoff_utc, goals_away - goals_home FROM finished
),
fixture_teams AS (
    SELECT fixture_id, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, kickoff_utc, away_team_id FROM fixtures
),
-- Por (fixture-alvo, time): nº de jogos anteriores na mesma liga e % derrotas/vitórias por 2+.
margin_stats AS (
    SELECT
        ft.fixture_id, ft.team_id,
        COUNT(*)             AS n_games,
        COUNTIF(r.margin <= -2) AS n_lost2,
        COUNTIF(r.margin >=  2) AS n_won2
    FROM fixture_teams ft
    JOIN team_results r
        ON r.team_id        = ft.team_id
       AND r.competition_id = ft.competition_id
       AND r.kickoff_utc    < ft.kickoff_utc
    GROUP BY ft.fixture_id, ft.team_id
),

-- Métricas brutas por outcome×linha.
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.line_value,
        o.s_is_home, o.side_handicap,
        (o.side_handicap < 0) AS is_favorito,
        (o.side_handicap > 0) AS is_azarao,

        -- ataque/defesa de S no campo deste jogo (tende_golear, defesa_fora_solida)
        IF(o.s_is_home, s.goals_for_avg_home,     s.goals_for_avg_away)     AS s_gf_venue,
        IF(o.s_is_home, s.goals_against_avg_home, s.goals_against_avg_away)  AS s_ga_venue,
        -- defesa de O no campo de O neste jogo (adversario_fragil_fora)
        IF(o.s_is_home, od.goals_against_avg_away, od.goals_against_avg_home) AS o_ga_venue,

        -- aproveitamento de S como mandante (mando_forte)
        (s.wins_home * 3 + s.draws_home) / NULLIF(s.played_home * 3, 0) * 100 AS pct_pts_home,

        -- tabela (supremacia)
        ss.rank                                AS s_rank,
        os.rank                                AS o_rank,
        ss.points / NULLIF(ss.played_total, 0) AS s_ppg,
        os.points / NULLIF(os.played_total, 0) AS o_ppg,
        ls.n_teams                             AS n_teams,

        -- margens (raramente_perde_por_2 = S; favorito_irregular = O)
        sm.n_games AS s_n_games, sm.n_lost2 AS s_lost2,
        om.n_games AS o_n_games, om.n_won2  AS o_won2
    FROM outcomes o
    LEFT JOIN tss s   ON s.team_id  = o.s_team_id AND s.season  = o.season AND s.competition_id  = o.competition_id
    LEFT JOIN tss od  ON od.team_id = o.o_team_id AND od.season = o.season AND od.competition_id = o.competition_id
    LEFT JOIN standings_latest ss ON ss.team_id = o.s_team_id AND ss.season = o.season AND ss.league_id = o.competition_id
    LEFT JOIN standings_latest os ON os.team_id = o.o_team_id AND os.season = o.season AND os.league_id = o.competition_id
    LEFT JOIN league_size ls      ON ls.league_id = o.competition_id AND ls.season = o.season
    LEFT JOIN margin_stats sm ON sm.fixture_id = o.fixture_id AND sm.team_id = o.s_team_id
    LEFT JOIN margin_stats om ON om.fixture_id = o.fixture_id AND om.team_id = o.o_team_id
),

-- Premissas (booleanos). Gated por favorito/azarão -> só o lado certo dispara; soma <=40 (fav) ou <=30 (dog).
flags AS (
    SELECT
        m.*,
        -- Favorito (Σ40)
        m.is_favorito AND (COALESCE(m.o_rank - m.s_rank >= 8, FALSE)
                           OR COALESCE(m.s_ppg >= 1.5 * m.o_ppg, FALSE))       AS supremacia,
        m.is_favorito AND COALESCE(m.s_gf_venue >= 2.0 AND m.s_ga_venue <= 1.0, FALSE) AS tende_golear,
        m.is_favorito AND COALESCE(m.o_ga_venue >= 1.6, FALSE)                  AS adversario_fragil_fora,
        m.is_favorito AND m.s_is_home AND COALESCE(m.pct_pts_home >= 60, FALSE) AS mando_forte,
        -- sem_rodizio = proxy COARSE de motivação (jogo importante, sem rodízio): só liga de
        -- pontos corridos (Brasileirão) e S em zona de disputa (G6 ou Z4). Copa -> FALSE (rank
        -- é por grupo, proxy não vale). TODO: refinar com rodada/congestionamento de calendário.
        m.is_favorito AND m.competition = 'brasileirao'
            AND COALESCE(m.s_rank <= 6 OR m.s_rank >= m.n_teams - 3, FALSE)     AS sem_rodizio,
        -- Azarão (Σ30)
        m.is_azarao AND COALESCE(m.s_n_games >= 5 AND m.s_lost2 / m.s_n_games < 0.30, FALSE) AS raramente_perde_por_2,
        m.is_azarao AND COALESCE(m.s_ga_venue <= 1.1, FALSE)                    AS defesa_fora_solida,
        m.is_azarao AND COALESCE(m.o_n_games >= 5 AND m.o_won2 / m.o_n_games < 0.35, FALSE)  AS favorito_irregular,
        -- penalidade específica (independe do lado): handicap alto raramente confiável
        (ABS(m.line_value) >= 2.5)                                             AS handicap_alto
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        (
            12 * CAST(f.supremacia             AS INT64)
          + 10 * CAST(f.tende_golear           AS INT64)
          +  8 * CAST(f.adversario_fragil_fora AS INT64)
          +  6 * CAST(f.mando_forte            AS INT64)
          +  4 * CAST(f.sem_rodizio            AS INT64)
          + 12 * CAST(f.raramente_perde_por_2  AS INT64)
          + 10 * CAST(f.defesa_fora_solida     AS INT64)
          +  8 * CAST(f.favorito_irregular     AS INT64)
        ) AS pts_premissas,
        12 * CAST(f.handicap_alto AS INT64) AS penalidades_ah_pts
    FROM flags f
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    line_value,
    side_handicap,
    is_favorito,
    is_azarao,
    -- flags (transparência/debug)
    supremacia,
    tende_golear,
    adversario_fragil_fora,
    mando_forte,
    sem_rodizio,
    raramente_perde_por_2,
    defesa_fora_solida,
    favorito_irregular,
    handicap_alto,
    -- agregados
    pts_premissas,
    penalidades_ah_pts,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(supremacia, 'claramente superior na tabela (rank/pontos)', NULL),
        IF(raramente_perde_por_2,
           FORMAT('raramente perde por 2+ (%d de %d jogos)', s_lost2, s_n_games), NULL),
        IF(tende_golear,
           FORMAT('tende a golear: marca %.1f e cede %.1f gol/jogo %s',
                  s_gf_venue, s_ga_venue, IF(s_is_home, 'em casa', 'fora')), NULL),
        IF(defesa_fora_solida,
           FORMAT('defesa sólida: cede só %.1f gol/jogo %s', s_ga_venue, IF(s_is_home, 'em casa', 'fora')), NULL),
        IF(adversario_fragil_fora,
           FORMAT('adversário frágil: cede %.1f gol/jogo %s', o_ga_venue, IF(s_is_home, 'fora', 'em casa')), NULL),
        IF(favorito_irregular,
           FORMAT('favorito irregular: vence por 2+ em só %d de %d jogos', o_won2, o_n_games), NULL),
        IF(mando_forte, FORMAT('%.0f%% de aproveitamento como mandante', pct_pts_home), NULL),
        IF(sem_rodizio, 'jogo importante na tabela (sem tendência a rodízio)', NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: penalidade específica do handicap.
    ARRAY(SELECT a FROM UNNEST([
        IF(handicap_alto,
           FORMAT('⚠ handicap alto (%.2f) — raramente confiável (−12)', line_value), NULL)
    ]) AS a WHERE a IS NOT NULL) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
