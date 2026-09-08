{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE COBERTURA DO FALLBACK DE ESTÁDIO (issue #150).
--
-- A API-Football só preenche o local do jogo perto do apito; antes disso manda `venue_id`
-- nulo mesmo quando o mandante já jogou em casa antes na nossa base — o estádio dele já está
-- em `fact_fixtures`, só não naquela linha específica. Medido em 05/09/2026: 1 em cada 3 jogos
-- futuros vinha sem estádio, com cobertura de 100% possível via "último estádio conhecido
-- desse mandante, olhando só pra trás no tempo" (ver ADR 0015).
--
-- Esta guarda torna essa alegação de cobertura uma invariante verificável, não uma medição de
-- um dia só: nenhuma fixture com `venue_id`/`venue_name`/`venue_city` nulo pode existir se o
-- mesmo `home_team_id` já tem alguma fixture ANTERIOR (por `kickoff_utc`) com AQUELA MESMA
-- coluna preenchida. As três são checadas em separado — medido (RB Bragantino, home_team_id
-- 794) que elas não chegam nulas sempre juntas da API, então uma guarda que olhasse só
-- venue_id deixaria dois terços da alegação de cobertura sem verificação nenhuma.
--
-- Point-in-time por desenho: só olha pra trás (`a.kickoff_utc < f.kickoff_utc`), nunca usa uma
-- fixture futura para cobrar uma passada — mesmo princípio que int_futebol_team_form_pit já usa
-- em outro lugar, mesmo o estádio não sendo insumo de premissa nenhuma (conferido contra
-- futebol_insumos_premissa() antes de escrever esta guarda).

WITH fixtures AS (
    SELECT fixture_id, home_team_id, kickoff_utc, venue_id, venue_name, venue_city
    FROM {{ ref('fact_fixtures') }}
    WHERE home_team_id IS NOT NULL
),

violacoes AS (
    SELECT fixture_id, home_team_id, kickoff_utc, 'venue_id' AS coluna
    FROM fixtures f
    WHERE f.venue_id IS NULL
      AND EXISTS (
          SELECT 1 FROM fixtures anterior
          WHERE anterior.home_team_id = f.home_team_id
            AND anterior.kickoff_utc < f.kickoff_utc
            AND anterior.venue_id IS NOT NULL
      )

    UNION ALL

    SELECT fixture_id, home_team_id, kickoff_utc, 'venue_name' AS coluna
    FROM fixtures f
    WHERE f.venue_name IS NULL
      AND EXISTS (
          SELECT 1 FROM fixtures anterior
          WHERE anterior.home_team_id = f.home_team_id
            AND anterior.kickoff_utc < f.kickoff_utc
            AND anterior.venue_name IS NOT NULL
      )

    UNION ALL

    SELECT fixture_id, home_team_id, kickoff_utc, 'venue_city' AS coluna
    FROM fixtures f
    WHERE f.venue_city IS NULL
      AND EXISTS (
          SELECT 1 FROM fixtures anterior
          WHERE anterior.home_team_id = f.home_team_id
            AND anterior.kickoff_utc < f.kickoff_utc
            AND anterior.venue_city IS NOT NULL
      )
)

SELECT * FROM violacoes
