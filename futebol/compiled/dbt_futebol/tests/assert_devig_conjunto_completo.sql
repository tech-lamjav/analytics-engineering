
-- GUARDA PRINCIPAL da regra de emissão (spec #22): nenhuma linha pode ter valor emitido se o
-- conjunto de saídas usado divergir do declarado no macro futebol_conjunto_saidas().
--
-- É a tradução literal do critério de aceite. Antes da correção, esta guarda pegaria 403 linhas
-- (61 do Handicap, 206 de Gols, 136 de Gols 1ºT) que normalizavam sobre UMA saída e devolviam
-- prob_justa = 1,0 e edge = odd − 1 — valor máximo anunciado onde o acerto real era 1,2%.
--
-- FALSIFICÁVEL HOJE, e isso é de propósito: as linhas rejeitadas continuam na tabela com
-- n_outcomes_valor honesto (só prob/booksum/edge/pts/fonte viram nulos). Remover a correção do
-- modelo deixa esta guarda vermelha imediatamente. Uma guarda que só é verde por não haver dado
-- para testá-la é infalsificável — esta não é.
--
-- Cobre também o fail-closed: mercado ausente do macro (esperado NULL) emitindo é falha.

WITH declarado AS (
    SELECT * FROM UNNEST([
        STRUCT(1 AS market_id, 3 AS conjunto_esperado),
        STRUCT(4 AS market_id, 2 AS conjunto_esperado),
        STRUCT(5 AS market_id, 2 AS conjunto_esperado),
        STRUCT(6 AS market_id, 2 AS conjunto_esperado),
        STRUCT(8 AS market_id, 2 AS conjunto_esperado),
        STRUCT(12 AS market_id, 3 AS conjunto_esperado)
    ])
)

SELECT
    v.market_id,
    d.conjunto_esperado,
    v.n_outcomes_valor,
    v.valor_fonte,
    COUNT(*)        AS linhas,
    MAX(v.edge)     AS edge_maximo,
    MAX(v.best_odd) AS odd_maxima
FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig` v
LEFT JOIN declarado d ON d.market_id = v.market_id
WHERE v.prob_justa_fechamento IS NOT NULL          -- só linhas que EMITIRAM valor
  AND (
        d.conjunto_esperado IS NULL                -- mercado não declarado emitindo (fail-closed furado)
     OR v.n_outcomes_valor IS NULL                 -- emitiu sem contagem de conjunto
     OR v.n_outcomes_valor <> d.conjunto_esperado  -- conjunto divergente do declarado
  )
GROUP BY 1, 2, 3, 4
ORDER BY linhas DESC