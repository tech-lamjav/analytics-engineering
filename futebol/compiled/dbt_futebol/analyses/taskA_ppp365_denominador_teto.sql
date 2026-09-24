

WITH teto AS (
    SELECT * FROM UNNEST([
        STRUCT('match_winner' AS market, 'Home'     AS lado, 51 AS teto),
        STRUCT('match_winner',           'Away',        47),
        STRUCT('match_winner',           'Draw',         0),
        STRUCT('goals_over_under',           'Over',        50),
        STRUCT('goals_over_under',           'Under',       46),
        STRUCT('asian_handicap',           'Favorito',    40),
        STRUCT('asian_handicap',           'Azarao',      30),
        STRUCT('asian_handicap',           'Pick',         0),
        STRUCT('btts',           'Yes',         34),
        STRUCT('btts',           'No',          28),
        STRUCT('double_chance',          'unico',       34)
    ])
),

recalculado AS (
    SELECT
        f.market,
        f.lado,
        f.passou_no_gate,
        f.nota_contexto,
        f.score_normalizado AS score_p95,
        t.teto,
        CASE
            WHEN f.nota_contexto IS NULL THEN NULL
            WHEN t.teto IS NULL OR t.teto <= 0 THEN 0
            ELSE LEAST(100, CAST(ROUND(f.nota_contexto / t.teto * 100) AS INT64))
        END AS score_v2
    FROM `smartbetting-dados`.`futebol`.`fact_value_funnel` f
    JOIN teto t USING (market, lado)
    WHERE f.janela_e_corrente
      AND f.score_normalizado IS NOT NULL
)

SELECT
    IF(passou_no_gate, 'board_publicado', 'funil_inteiro') AS populacao,
    market,
    lado,
    COUNT(*)                                              AS n,
    ROUND(100 * COUNTIF(score_p95 = 100) / COUNT(*), 1)   AS pct_no_teto_com_p95,
    ROUND(100 * COUNTIF(score_v2  = 100) / COUNT(*), 1)   AS pct_no_teto_com_teto,
    ROUND(AVG(score_p95), 1)                              AS media_p95,
    ROUND(AVG(score_v2), 1)                                AS media_teto,
    COUNTIF(score_v2 < 24)                                AS baixa_corte_24_47,
    COUNTIF(score_v2 BETWEEN 24 AND 46)                   AS media_corte_24_47,
    COUNTIF(score_v2 >= 47)                               AS alta_corte_24_47
FROM recalculado
GROUP BY GROUPING SETS (
    (populacao, market, lado),
    (populacao)
)
ORDER BY populacao DESC, market, lado