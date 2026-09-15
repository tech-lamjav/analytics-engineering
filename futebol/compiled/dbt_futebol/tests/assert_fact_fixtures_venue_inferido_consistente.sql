
-- GUARDA DE CONSISTÊNCIA DA FLAG `venue_inferido` (issue #150).
--
-- `venue_inferido` marca que ao menos um de venue_id/venue_name/venue_city veio do fallback
-- (último conhecido do mandante), não direto da API. Medido em 08/09/2026: os três campos NÃO
-- viajam sempre juntos — há fixture com venue_name preenchido e venue_id nulo na mesma linha
-- (RB Bragantino, home_team_id 794) — por isso o fallback é aplicado por coluna, não em bloco,
-- e a flag é um OR das três, não a nulidade de uma só.
--
-- Esta guarda prova a outra direção do contrato: `venue_inferido = TRUE` só pode acontecer numa
-- linha onde exista mesmo uma fixture ANTERIOR do mesmo mandante com pelo menos um dos três
-- campos preenchido. Sem esta guarda, um bug na window function poderia marcar `venue_inferido`
-- em toda fixture com QUALQUER campo nulo — inclusive nas 2 de cada 3 fixtures futuras onde o
-- mandante nunca jogou em casa antes na nossa base, e para as quais nenhum fallback é possível.

WITH fixtures AS (
    SELECT fixture_id, home_team_id, kickoff_utc, venue_id, venue_name, venue_city, venue_inferido
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE home_team_id IS NOT NULL
)

SELECT
    f.fixture_id,
    f.home_team_id,
    f.kickoff_utc
FROM fixtures f
WHERE f.venue_inferido
  AND NOT EXISTS (
      SELECT 1
      FROM fixtures anterior
      WHERE anterior.home_team_id = f.home_team_id
        AND anterior.kickoff_utc < f.kickoff_utc
        AND (anterior.venue_id IS NOT NULL OR anterior.venue_name IS NOT NULL OR anterior.venue_city IS NOT NULL)
  )