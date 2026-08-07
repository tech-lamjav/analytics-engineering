

WITH fixtures AS (
    SELECT fixture_id, kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- (D) Janela PRÉ-JOGO: descarta o log retroativo. Sem isto, o backtest lê lesões registradas
-- depois do apito — inclusive as que aconteceram durante o próprio jogo.
inj_pregame AS (
    SELECT
        i.fixture_id,
        i.team_id,
        i.player_id,
        i.player_name,
        i.injury_type,
        i.injury_reason,
        i.league_id,
        i.snapshot_date
    FROM `smartbetting-dados`.`futebol`.`fact_injuries_snapshot` i
    JOIN fixtures f USING (fixture_id)
    WHERE i.extracted_at < f.kickoff_utc
),

inj_latest AS (
    SELECT * EXCEPT (snapshot_date)
    FROM inj_pregame
    -- snapshot mais recente ANTES do apito (o histórico acumula no fato; vale o último pré-jogo).
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

-- (E) Importância POINT-IN-TIME. Log cumulativo de minutos/titularidades do jogador ATÉ cada
-- jogo dele; a leitura pega o estado do último jogo ANTERIOR ao kickoff do jogo-alvo. Window
-- function, sem cross join — o pool de todas as seasons era o resíduo de look-ahead do item E.
player_log AS (
    SELECT
        ps.player_id,
        ps.competition_id,
        f.kickoff_utc,
        SUM(ps.minutes)                             OVER w AS cum_minutes,
        SUM(IF(ps.is_substitute = FALSE, 1, 0))     OVER w AS cum_starts,
        COUNT(*)                                    OVER w AS cum_games,
        AVG(ps.rating)                              OVER w AS cum_rating
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_player_stats` ps
    JOIN fixtures f USING (fixture_id)
    WINDOW w AS (
        PARTITION BY ps.player_id, ps.competition_id
        ORDER BY f.kickoff_utc
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
),

importance_pit AS (
    SELECT
        d.fixture_id,
        d.team_id,
        d.player_id,
        pl.cum_minutes,
        pl.cum_starts,
        pl.cum_games,
        pl.cum_rating
    FROM inj_dedup d
    JOIN fixtures f ON f.fixture_id = d.fixture_id
    LEFT JOIN player_log pl
        ON  pl.player_id      = d.player_id
        AND pl.competition_id = d.league_id
        AND pl.kickoff_utc    < f.kickoff_utc
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY d.fixture_id, d.team_id, d.player_id
        ORDER BY pl.kickoff_utc DESC
    ) = 1
),

-- Proxy pooled (todas as seasons), mantido só p/ comparação/front — NÃO alimenta a premissa.
importance_pooled AS (
    SELECT player_id, competition_id, is_important
    FROM `smartbetting-dados`.`futebol`.`int_futebol_player_importance`
)

SELECT
    i.fixture_id,
    i.team_id,
    i.player_id,
    i.player_name,
    i.injury_type,                       -- 'Missing Fixture' (fora) | 'Questionable' (dúvida)
    i.injury_reason,

    -- titular regular ATÉ o jogo (mesmos thresholds do proxy: >=450 min e >=50% de titularidade)
    COALESCE(
        p.cum_minutes >= 450 AND SAFE_DIVIDE(p.cum_starts, p.cum_games) >= 0.5,
        FALSE
    )                                  AS is_important,
    COALESCE(pool.is_important, FALSE) AS is_important_pooled,

    SAFE_DIVIDE(p.cum_starts, p.cum_games) AS start_share,
    p.cum_minutes                      AS total_minutes,
    p.cum_rating                       AS avg_rating,
    COALESCE(p.cum_games, 0)           AS importance_games,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM inj_dedup i
LEFT JOIN importance_pit p
    ON  p.fixture_id = i.fixture_id
    AND p.team_id    = i.team_id
    AND p.player_id  = i.player_id
LEFT JOIN importance_pooled pool
    ON  pool.player_id      = i.player_id
    AND pool.competition_id = i.league_id