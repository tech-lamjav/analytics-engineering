{{ config(
    description='Flatten do raw_futebol_fixtures. NÃO é 1 linha por fixture — é 1 linha por EXTRAÇÃO: raw_futebol_fixtures é append-only e o extractor re-busca jogo recente pra pegar status/placar atualizado, então o mesmo fixture_id repete com loaded_at maior (ver models.yml, corrigido 02/09/2026). Apenas a espinha (/fixtures): fixture, league, teams, goals, score. Stats/events/lineups vêm de endpoints separados (subtasks 5-8). fact_fixtures deriva competition/date_utc e faz o dedup de verdade (latest-wins por loaded_at).'
) }}

-- CORTE DAS COMPETIÇÕES DE INSUMO POR DATA DE ENTRADA — DE#96 (data-engineering), ADR 0004 lá
-- ("competição de insumo"), seção "Medição (DE#95)". Data e liga vêm de
-- macros/futebol_competicoes_insumo.sql, que explica o porquê e é a fonte única.
--
-- Amistosos de seleção (league_id 10) chegam ao raw com a temporada inteira (DE#94 ligou a
-- coleta com o universo cortado), mas só entram no mart os jogos com kickoff a partir de
-- 2026-09-23. A #95 mediu que o passado (115 FT, jan–jun) deslocaria em ~23 pp a forma PIT de
-- âncoras de Copa do Mundo e Nations League já medidas — a forma atravessa competição desde a
-- #91/ADR 0010 de lá — e o veredito foi que o passado não entra. Este corte é PERMANENTE: o raw
-- continua trazendo os 115 (a tabela externa é wildcard sobre o GCS, não há portão entre o
-- bucket e o mart), então tirá-lo publicaria exatamente o deslocamento que a #95 recusou. A
-- guarda assert_competicao_insumo_sem_passado acende se isso acontecer.
--
-- Até a #96 este mesmo ponto bloqueava a liga 10 INTEIRA (corte temporário da #94). Continua
-- sendo aqui pelo mesmo motivo: é o ponto MAIS CEDO do DAG que lê o raw (único model que faz
-- `source(...)` sobre raw_futebol_fixtures; fact_fixtures é o único que lê este model).
--
-- MEDIÇÃO (DE#95): var `taskf_incluir_amistosos`, default false. Com ela, o corte some e o
-- passado entra — só existe para o cenário "com amistosos" da análise
-- taskf_amistosos_efeito_retroativo_95 continuar reproduzível contra o target `taskF`, nunca
-- contra dev/prod.
{% set aplica_corte_insumo = not var('taskf_incluir_amistosos', false) %}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_fixtures') }}
    {% if aplica_corte_insumo -%}
    WHERE NOT {{ futebol_insumo_antes_da_entrada('requested_league_id', 'TIMESTAMP_SECONDS(fixture.timestamp)') }}
    {%- endif %}
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
