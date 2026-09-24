

WITH premissas_1x2 AS (
    SELECT fixture_id, outcome, insumos_medidos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
),

-- AE#202: Handicap asiático. line_value é o handicap na ótica do MANDANTE, o mesmo valor que o
-- funil e o board carregam — o front casa por ele sem converter.
premissas_ah AS (
    SELECT fixture_id, outcome, line_value, insumos_medidos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
)

SELECT
    p.fixture_id,
    p.outcome,
    'match_winner' AS market,
    CAST(NULL AS FLOAT64) AS line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM premissas_1x2 AS p,
UNNEST(p.insumos_medidos) AS im

UNION ALL

SELECT
    p.fixture_id,
    p.outcome,
    'asian_handicap' AS market,
    p.line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM premissas_ah AS p,
UNNEST(p.insumos_medidos) AS im