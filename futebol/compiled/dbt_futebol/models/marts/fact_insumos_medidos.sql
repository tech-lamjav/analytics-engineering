

SELECT
    p.fixture_id,
    p.outcome,
    'match_winner' AS market,
    CAST(NULL AS FLOAT64) AS line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2` AS p,
UNNEST(p.insumos_medidos) AS im