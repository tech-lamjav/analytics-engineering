

WITH deduplicado AS (
SELECT
    fixture_id,
    CASE requested_league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        WHEN 72 THEN 'serie_b'
        WHEN 73 THEN 'copa_do_brasil'
        WHEN 13 THEN 'libertadores'
        WHEN 11 THEN 'sudamericana'
        WHEN 140 THEN 'la_liga'
        WHEN 39 THEN 'premier_league'
        WHEN 2  THEN 'champions_league'
        WHEN 135 THEN 'serie_a_ita'
        WHEN 78  THEN 'bundesliga'
        WHEN 61  THEN 'ligue_1'
        WHEN 94  THEN 'primeira_liga'
        WHEN 5  THEN 'nations_league'
        -- Competição de INSUMO (ADR 0004 no data-engineering, decisão 15): o slug entra SÓ aqui,
        -- nunca nos outros cinco CASE — lá ele sugeriria cobertura de odds/tabela/desfalque/
        -- previsão/stats de temporada que não coletamos. Ver macros/futebol_competicoes_insumo.sql.
        WHEN 10 THEN 'amistosos'
        ELSE 'unknown'
    END                                          AS competition,
    requested_league_id                          AS competition_id,
    requested_season                             AS season,
    round,

    -- tempo (epoch UTC = inequívoco; date_utc é a chave de partição)
    DATE(TIMESTAMP_SECONDS(timestamp_unix))      AS date_utc,
    TIMESTAMP_SECONDS(timestamp_unix)            AS kickoff_utc,
    timestamp_unix,
    timezone,

    -- status do jogo
    status_long,
    status_short,
    status_elapsed,

    -- local / arbitragem
    referee,
    venue_id,
    venue_name,
    venue_city,

    -- times (home_team_id participa do cluster)
    home_team_id,
    home_team_name,
    home_team_winner,
    away_team_id,
    away_team_name,
    away_team_winner,

    -- placar
    goals_home,
    goals_away,
    score_halftime_home,
    score_halftime_away,
    score_fulltime_home,
    score_fulltime_away,
    score_extratime_home,
    score_extratime_away,
    score_penalty_home,
    score_penalty_away,

    loaded_at           AS extracted_at
FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixtures`
-- NÃO é defensivo: fixture_id NÃO é único em stg_futebol_fixtures (o extractor
-- re-busca jogo recente e a mesma fixture entra de novo com loaded_at maior — corrigido
-- na description do modelo em 02/09/2026). Este QUALIFY é o dedup de verdade, latest-wins
-- por loaded_at. Mantém o idioma de dedup de dim_players/dim_teams.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY fixture_id
    ORDER BY loaded_at DESC
) = 1
),

-- FALLBACK DE ESTÁDIO (issue #150, ADR 0015): a API só manda o local perto do apito; antes
-- disso vem NULL mesmo quando o mandante já jogou em casa antes na nossa base. Point-in-time
-- por PRINCÍPIO, não por medo de look-ahead — o estádio não é insumo de premissa nenhuma
-- (conferido contra futebol_insumos_premissa() antes de escrever isto) — mas o mesmo princípio
-- de int_futebol_team_form_pit (só olhar estritamente pra trás no tempo) vale aqui por
-- consistência. Mecanismo diferente do de lá, de propósito: team_form_pit é self-join com
-- `l.kickoff_utc < a.kickoff_utc`; aqui é LAST_VALUE(... IGNORE NULLS) sobre uma janela — não
-- é "o mesmo idioma", é o mesmo PRINCÍPIO com mecanismo mais barato para este caso (1 coluna
-- por vez, sem cruzar a tabela consigo mesma).
--
-- ORDER BY kickoff_utc NULLS LAST + fixture_id como desempate: nem timestamp_unix nem
-- home_team_id têm not_null hoje (a fonte nunca mandou nulo até 08/09/2026, medido), mas nada
-- impede um dia mandar. Sem NULLS LAST, uma fixture de kickoff nulo ordenaria PRIMEIRO (default
-- do BigQuery é NULLS FIRST) e poderia "vazar" seu venue pra trás, pra fixtures com kickoff
-- real anterior — exatamente o que este fallback promete nunca fazer. fixture_id desempata
-- kickoff empatado (hoje também não ocorre, medido) sem depender de ordem de leitura da tabela.
--
-- home_team_id NULO nunca CONSOME o fallback (ainda que participe da janela): sem isso, duas
-- fixtures de times DIFERENTES que por acaso tenham home_team_id nulo cairiam na mesma partição
-- e uma poderia herdar o estádio da outra. Hoje home_team_id nunca é nulo (medido), mas o
-- COALESCE abaixo é condicionado a `home_team_id IS NOT NULL` para que isso continue verdade
-- mesmo se a fonte mudar.
--
-- Os três campos NÃO viajam sempre juntos: medido (RB Bragantino, home_team_id 794) uma
-- fixture com venue_name preenchido e venue_id nulo na mesma linha. Por isso o fallback é
-- por coluna, não em bloco, e venue_inferido é um OR das três, não a nulidade de uma só.
com_ultimo_venue_conhecido AS (
    SELECT
        fixture_id,
        home_team_id,
        venue_id,
        venue_name,
        venue_city,
        LAST_VALUE(venue_id IGNORE NULLS) OVER (
            PARTITION BY home_team_id ORDER BY kickoff_utc NULLS LAST, fixture_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS venue_id_ultimo_conhecido,
        LAST_VALUE(venue_name IGNORE NULLS) OVER (
            PARTITION BY home_team_id ORDER BY kickoff_utc NULLS LAST, fixture_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS venue_name_ultimo_conhecido,
        LAST_VALUE(venue_city IGNORE NULLS) OVER (
            PARTITION BY home_team_id ORDER BY kickoff_utc NULLS LAST, fixture_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS venue_city_ultimo_conhecido
    FROM deduplicado
)

SELECT
    d.fixture_id,
    d.competition,
    d.competition_id,
    d.season,
    d.round,
    d.date_utc,
    d.kickoff_utc,
    d.timestamp_unix,
    d.timezone,
    d.status_long,
    d.status_short,
    d.status_elapsed,
    d.referee,
    COALESCE(d.venue_id, IF(d.home_team_id IS NOT NULL, v.venue_id_ultimo_conhecido, NULL))     AS venue_id,
    COALESCE(d.venue_name, IF(d.home_team_id IS NOT NULL, v.venue_name_ultimo_conhecido, NULL)) AS venue_name,
    COALESCE(d.venue_city, IF(d.home_team_id IS NOT NULL, v.venue_city_ultimo_conhecido, NULL)) AS venue_city,
    d.home_team_id IS NOT NULL AND (
        (d.venue_id IS NULL AND v.venue_id_ultimo_conhecido IS NOT NULL)
        OR (d.venue_name IS NULL AND v.venue_name_ultimo_conhecido IS NOT NULL)
        OR (d.venue_city IS NULL AND v.venue_city_ultimo_conhecido IS NOT NULL)
    ) AS venue_inferido,
    d.home_team_id,
    d.home_team_name,
    d.home_team_winner,
    d.away_team_id,
    d.away_team_name,
    d.away_team_winner,
    d.goals_home,
    d.goals_away,
    d.score_halftime_home,
    d.score_halftime_away,
    d.score_fulltime_home,
    d.score_fulltime_away,
    d.score_extratime_home,
    d.score_extratime_away,
    d.score_penalty_home,
    d.score_penalty_away,
    d.extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM deduplicado d
JOIN com_ultimo_venue_conhecido v USING (fixture_id)
-- FILTRO INCREMENTAL (AE#191): de propósito só AQUI, na ponta final — não empurrado pra
-- dentro de `deduplicado`. O fallback de venue (CTE acima) precisa ver o HISTÓRICO INTEIRO
-- de cada home_team_id pra funcionar (LAST_VALUE sobre a janela completa); filtrar a fonte
-- cedo demais quebraria o fallback pra qualquer fixture fora do lote incremental.
--
-- Anti-join por fixture_id, NÃO um cursor global tipo `extracted_at > MAX(extracted_at)`:
-- um cursor global é uma corrida entre fontes — um backfill de temporada com loaded_at mais
-- antigo que chega DEPOIS de um poll do fixtures-live já ter avançado o máximo global seria
-- descartado em silêncio. Comparar por fixture_id é correto não importa a ordem de chegada.

WHERE NOT EXISTS (
    SELECT 1 FROM `smartbetting-dados`.`futebol`.`fact_fixtures` t
    WHERE t.fixture_id = d.fixture_id
      AND t.extracted_at >= d.extracted_at
)
