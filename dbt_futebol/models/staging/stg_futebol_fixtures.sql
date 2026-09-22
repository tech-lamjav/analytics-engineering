{{ config(
    description='Flatten do raw_futebol_fixtures. NÃO é 1 linha por fixture — é 1 linha por EXTRAÇÃO: raw_futebol_fixtures é append-only e o extractor re-busca jogo recente pra pegar status/placar atualizado, então o mesmo fixture_id repete com loaded_at maior (ver models.yml, corrigido 02/09/2026). Apenas a espinha (/fixtures): fixture, league, teams, goals, score. Stats/events/lineups vêm de endpoints separados (subtasks 5-8). fact_fixtures deriva competition/date_utc e faz o dedup de verdade (latest-wins por loaded_at).'
) }}

-- CORTE TEMPORÁRIO — DE#94/DE#95/DE#96 (data-engineering), ADR 0004 lá ("competição de
-- insumo"). Amistosos de seleção (league_id 10) já chegam no raw (DE#94 ligou a coleta com
-- universo cortado), mas NÃO podem entrar em produção ainda: ligar os 115 jogos finalizados
-- move retroativamente a forma PIT das seleções que já têm linha em fact_fixtures (a forma
-- atravessa competição desde a #91/ADR 0010 de lá), e isso só é seguro se medido primeiro
-- (DE#95, contra o target futebol_taskF, nunca produção).
--
-- Filtrado aqui — o ponto MAIS CEDO do DAG que lê o raw (único model que faz `source(...)`
-- sobre raw_futebol_fixtures; fact_fixtures é o único que lê este model) — para proteger
-- fact_fixtures e os 6 marts que derivam league_id dela (odds/predictions/standings/
-- injuries/team_season_stats — os "6 CASE" citados em models.yml) numa linha só, em vez de
-- repetir o filtro em cada um.
-- REMOVER quando o DE#95 der veredito favorável e o DE#96 ligar o slug 'amistosos' nos
-- marts — a lista abaixo é a única coisa que precisa sair.
{% set ligas_insumo_bloqueadas_ate_medicao = [10] %}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_fixtures') }}
    WHERE requested_league_id NOT IN ({{ ligas_insumo_bloqueadas_ate_medicao | join(',') }})
)

SELECT
    src.requested_league_id,
    src.requested_season,
    src.loaded_at,

    -- fixture
    src.fixture.id              AS fixture_id,
    src.fixture.referee         AS referee,
    src.fixture.timezone        AS timezone,
    src.fixture.timestamp       AS timestamp_unix,  -- epoch UTC (base do date_utc)
    src.fixture.venue.id        AS venue_id,
    src.fixture.venue.name      AS venue_name,
    src.fixture.venue.city      AS venue_city,
    src.fixture.status.long     AS status_long,
    src.fixture.status.short    AS status_short,
    src.fixture.status.elapsed  AS status_elapsed,

    -- league
    src.league.round            AS round,

    -- teams
    {{ futebol_team_id_canonico('src.teams.home.id') }} AS home_team_id,
    src.teams.home.name         AS home_team_name,
    src.teams.home.winner       AS home_team_winner,
    {{ futebol_team_id_canonico('src.teams.away.id') }} AS away_team_id,
    src.teams.away.name         AS away_team_name,
    src.teams.away.winner       AS away_team_winner,

    -- goals (tempo normal)
    src.goals.home              AS goals_home,
    src.goals.away              AS goals_away,

    -- score (por etapa)
    src.score.halftime.home     AS score_halftime_home,
    src.score.halftime.away     AS score_halftime_away,
    src.score.fulltime.home     AS score_fulltime_home,
    src.score.fulltime.away     AS score_fulltime_away,
    src.score.extratime.home    AS score_extratime_home,
    src.score.extratime.away    AS score_extratime_away,
    src.score.penalty.home      AS score_penalty_home,
    src.score.penalty.away      AS score_penalty_away
FROM src
