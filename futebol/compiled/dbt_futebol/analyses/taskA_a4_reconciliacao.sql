

WITH universo AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.line_value,
        f.kickoff_utc,
        CASE f.market
        WHEN 'match_winner' THEN
            IF(f.outcome IN ('Home', 'Draw', 'Away'), f.outcome, NULL)
        WHEN 'goals_over_under' THEN
            IF(f.outcome IN ('Over', 'Under'), f.outcome, NULL)
        WHEN 'btts' THEN
            IF(f.outcome IN ('Yes', 'No'), f.outcome, NULL)
        WHEN 'double_chance' THEN
            IF(f.outcome IN ('1X', 'X2'), 'unico', NULL)
        WHEN 'asian_handicap' THEN
            CASE
                WHEN f.outcome NOT IN ('Home', 'Away') THEN NULL
                -- o handicap na ótica do lado apostado; `line_value` vem na do mandante.
                WHEN IF(f.outcome = 'Home', f.line_value, -f.line_value) < 0 THEN 'Favorito'
                WHEN IF(f.outcome = 'Home', f.line_value, -f.line_value) > 0 THEN 'Azarao'
                -- linha 0 (B3, #109): a odd decide quem é favorito, mando só desempata
                -- odds iguais (ou ausentes). MESMA regra em `int_futebol_premissas_ah`
                -- (is_favorito/is_azarao); os dois têm de concordar, porque é esta coluna
                -- que casa a linha com o p95 do lado.
                WHEN IF(f.outcome = 'Home', f.line_value, -f.line_value) = 0
                    THEN IF(
                        f.outcome = 'Home',
                        'Favorito', 'Azarao'
                    )
                -- handicap ausente: não dá para dizer o lado, e inventá-lo é pior.
                ELSE NULL
            END
    END AS lado
    FROM `smartbetting-dados`.`futebol`.`fact_value_funnel` f
    -- uma janela por candidato, exatamente como a `taskA_a6_p95.sql`.
    WHERE f.janela_e_corrente
      -- o recorte de kickoff que o seed carimba em `janela_inicio` / `janela_fim`.
      AND DATE(f.kickoff_utc) BETWEEN DATE '2026-06-16' AND DATE '2026-08-31'
),recomputado AS (
    SELECT u.*, p.pts_premissas, p.penalidades_1x2_pts AS penalidades_especificas_pts
    FROM universo u
    JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2` p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
    WHERE u.market = 'match_winner'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_ou_pts
    FROM universo u
    JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou` p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
     AND COALESCE(CAST(p.line_value AS STRING), 'NONE') = u.line_key
    WHERE u.market = 'goals_over_under'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_ah_pts
    FROM universo u
    JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah` p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
     AND COALESCE(CAST(p.line_value AS STRING), 'NONE') = u.line_key
    WHERE u.market = 'asian_handicap'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_btts_pts
    FROM universo u
    JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts` p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
    WHERE u.market = 'btts'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_dc_pts
    FROM universo u
    JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc` p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
    WHERE u.market = 'double_chance'
),

com_nota AS (
    SELECT r.*, GREATEST(pts_premissas - penalidades_especificas_pts, 0) AS nota_contexto
    FROM recomputado r
    WHERE r.lado IS NOT NULL
),

medido AS (
    SELECT DISTINCT
        market,
        lado,
        PERCENTILE_DISC(nota_contexto, 0.95) OVER (PARTITION BY market, lado) AS p95_recomputado,
        COUNT(*) OVER (PARTITION BY market, lado)                           AS n_recomputado
    FROM com_nota
)

SELECT
    m.market,
    m.lado,
    s.p95                          AS p95_seed,
    m.p95_recomputado,
    m.p95_recomputado - s.p95      AS desvio,
    s.n_candidatos                 AS n_seed,
    m.n_recomputado,
    CASE
        WHEN s.p95 = 0 AND m.p95_recomputado = 0             THEN 'OK (zero estrutural)'
        WHEN s.p95 = 0 OR  m.p95_recomputado = 0             THEN 'FALHA (zero de um lado só)'
        WHEN ABS(m.p95_recomputado - s.p95) <= 2             THEN 'OK'
        ELSE                                                      'FALHA (fora de +-2)'
    END AS veredito
FROM medido m
-- FULL OUTER de propósito: lado no seed e ausente da recomputação (ou o inverso) tem de
-- aparecer como linha, nunca sumir no join. Cobertura é metade do que esta análise prova.
FULL OUTER JOIN `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto` s
  ON s.market = m.market AND s.lado = m.lado
ORDER BY m.market, m.lado