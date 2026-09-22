{{ config(tags=['guarda'], severity='error') }}
-- CORTE TEMPORÁRIO (DE#94/DE#95/DE#96 no data-engineering, ADR 0004 lá) — trava de
-- regressão do corte em stg_futebol_fixtures.sql (WHERE requested_league_id NOT IN (10)).
--
-- Amistosos de seleção (league_id 10) são competição de INSUMO: já chegam no raw (DE#94
-- ligou a coleta com universo cortado), mas não podem entrar em produção até o DE#95 medir
-- o efeito retroativo no histórico PIT das seleções (a forma atravessa competição desde a
-- #91/ADR 0010 de lá) e dar veredito favorável.
--
-- Se este teste acender, o corte upstream foi removido ou contornado sem que o DE#95 tivesse
-- rodado — não é "dia 1 de cobertura parcial" (esse caso é o gêmeo
-- assert_per_fixture_coverage_anomala), é o portão inteiro furado.
--
-- REMOVER junto com o corte em stg_futebol_fixtures.sql quando o DE#96 ligar o slug
-- 'amistosos' nos marts.

SELECT competition_id, COUNT(*) AS jogos
FROM {{ ref('fact_fixtures') }}
WHERE competition_id = 10
GROUP BY competition_id
