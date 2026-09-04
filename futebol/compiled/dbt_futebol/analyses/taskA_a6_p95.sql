

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
    -- uma janela por candidato — ver o ⚠️ do cabeçalho.
    WHERE f.janela_e_corrente
),

-- ============================================================================
-- A RECOMPUTAÇÃO. O universo (esquerda) vem do funil; os pontos (direita) vêm dos cinco
-- modelos de premissa como eles estão hoje. As chaves de junção são as MESMAS que o
-- `fact_value_funnel` usa em cada ramo — copiá-las diferente aqui mediria outra coisa.
-- ============================================================================
recomputado AS (
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
    SELECT
        r.*,
        -- a MESMA composição que o funil grava, do mesmo macro. As duas colunas de que ele
        -- depende chegam acima com o nome que ele espera.
        GREATEST(pts_premissas - penalidades_especificas_pts, 0) AS nota_contexto
    FROM recomputado r
    -- saída fora do catálogo (a "12" da DC) resolve o lado para NULL e sai da medição.
    WHERE r.lado IS NOT NULL
),

medido AS (
    SELECT DISTINCT
        market,
        lado,
        PERCENTILE_DISC(nota_contexto, 0.95) OVER (PARTITION BY market, lado) AS p95,
        COUNT(*)                OVER (PARTITION BY market, lado) AS n_candidatos,
        COUNTIF(nota_contexto IS NOT NULL)
                                OVER (PARTITION BY market, lado) AS n_avaliados,
        MAX(nota_contexto)      OVER (PARTITION BY market, lado) AS maximo_observado,
        AVG(nota_contexto)      OVER (PARTITION BY market, lado) AS media_observada,
        COUNTIF(nota_contexto = 0)
                                OVER (PARTITION BY market, lado) AS n_em_zero,
        MIN(DATE(kickoff_utc))  OVER (PARTITION BY market, lado) AS janela_inicio,
        MAX(DATE(kickoff_utc))  OVER (PARTITION BY market, lado) AS janela_fim
    FROM com_nota
)

SELECT
    market,
    lado,
    p95,
    -- o teto do catálogo, escrito à mão, para conferir de olho quem SATURA (p95 = teto) e
    -- quem não chega perto. Os três valores que a tabela de origem errava estão aqui
    -- corrigidos: 1X2 Away 47, 1X2 Draw 0, BTTS No 28.
    CASE market || '/' || lado
        WHEN 'match_winner/Home'     THEN 51
        WHEN 'match_winner/Away'     THEN 47
        WHEN 'match_winner/Draw'     THEN 0
        WHEN 'goals_over_under/Over'     THEN 50
        WHEN 'goals_over_under/Under'    THEN 46
        WHEN 'asian_handicap/Favorito' THEN 40
        WHEN 'asian_handicap/Azarao'   THEN 30
        WHEN 'asian_handicap/Pick'     THEN 0
        WHEN 'btts/Yes'      THEN 34
        WHEN 'btts/No'       THEN 28
        WHEN 'double_chance/unico'   THEN 34
    END AS teto_catalogo,
    n_candidatos,
    n_avaliados,
    n_em_zero,
    maximo_observado,
    ROUND(media_observada, 2) AS media_observada,
    -- quanto a nota normalizada mudaria a média deste lado — a amplitude que a ADR 0005
    -- diz que cai de 3,8× para 2,1×, e que NÃO some.
    ROUND(SAFE_DIVIDE(media_observada, p95) * 100, 1) AS media_normalizada,
    janela_inicio,
    janela_fim
FROM medido
ORDER BY market, lado