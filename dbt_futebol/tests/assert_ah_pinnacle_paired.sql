-- Guarda do pareamento do Handicap asiático (market 4) da Pinnacle (bookmaker 4): o de-vig do
-- AH depende de cada (fixture, line_value) ter os DOIS lados complementares (Home + Away) na
-- MESMA line_value — porque a API-Football traz o handicap na ÓTICA DO MANDANTE, igual p/ Home e
-- Away (confirmado vs. dados reais 2026-06-26). Se a API algum dia inverter o sinal do lado
-- visitante (ex.: passar a mandar 'Away +1.5' em vez de 'Away -1.5'), Home e Away caem em
-- line_value diferentes, cada grupo fica com 1 lado, o gate pin_n_outcomes>=2 zera o AH
-- silenciosamente (mercado "verde mas vazio") e o is_favorito do prem_ah inverte. Este teste
-- retorna (= falha) qualquer grupo (fixture, line) da Pinnacle no AH sem exatamente os 2 lados.
-- Passa em tabela vazia / quando ainda não há AH da Pinnacle.
SELECT
    fixture_id,
    line_value,
    COUNT(DISTINCT outcome_side) AS n_sides,
    COUNT(*)                     AS n_rows
FROM {{ ref('fact_odds_snapshot') }}
WHERE market_id = 4      -- Asian Handicap
  AND bookmaker_id = 4   -- Pinnacle (sharp de referência do de-vig)
GROUP BY fixture_id, line_value
HAVING COUNT(DISTINCT outcome_side) <> 2
