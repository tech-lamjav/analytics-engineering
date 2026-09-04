WITH universo AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.line_value,
        f.kickoff_utc,
        f.best_odd,
        f.n_casas,
        f.pen_odd_outlier,
        f.prob_justa_fechamento,
        f.porta_saida_catalogada,
        f.porta_cobertura_pinnacle,
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
    WHERE f.janela_e_corrente
      AND f.gravado_em < TIMESTAMP '2026-08-28 21:00:00'
      AND f.kickoff_utc < TIMESTAMP '2026-08-28 21:00:00'
),jogos AS (
    SELECT fixture_id, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND goals_away IS NOT NULL
),

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
),com_nota AS (
    SELECT
        r.*,
        CASE r.market
            WHEN 'match_winner' THEN 1
            WHEN 'asian_handicap' THEN 4
            WHEN 'goals_over_under' THEN 5
            WHEN 'btts' THEN 8
            WHEN 'double_chance' THEN 12
        END AS market_id,
        -- o `task01_liquidacao()` chaveia por `outcome_side`; o funil chama a mesma coisa
        -- de `outcome`. Renomear aqui, e não reescrever o macro, mantém a liquidação
        -- byte a byte a mesma que produziu os números publicados da [0.1].
        r.outcome AS outcome_side,
        GREATEST(pts_premissas - penalidades_especificas_pts, 0) AS nota_contexto
    FROM recomputado r
    WHERE r.lado IS NOT NULL
),

normalizado AS (
    SELECT
        c.*,
        s.p95,
        CASE
        WHEN nota_contexto IS NULL      THEN NULL
        WHEN teto IS NULL OR teto <= 0  THEN 0
        ELSE LEAST(100, CAST(ROUND(nota_contexto / teto * 100) AS INT64))
    END AS score_normalizado
    FROM com_nota c
    -- LEFT: lado ausente do seed vira denominador NULL e o macro o resolve para zero
    -- visível, nunca NULL silencioso. Quem cobra ausência é a guarda de cobertura.
    LEFT JOIN `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto` s
           ON s.market = c.market AND s.lado = c.lado
),publicavel AS (
    SELECT
        n.*,
        j.goals_home,
        j.goals_away,
        
    CASE
        WHEN n.market_id = 1 THEN
            CASE n.outcome_side
                WHEN 'Home' THEN j.goals_home > j.goals_away
                WHEN 'Away' THEN j.goals_away > j.goals_home
                ELSE             j.goals_home = j.goals_away
            END
        WHEN n.market_id = 5 THEN
            IF(n.outcome_side = 'Over',
               j.goals_home + j.goals_away > n.line_value,
               j.goals_home + j.goals_away < n.line_value)
        -- line_value vem na ÓTICA DO MANDANTE e é igual p/ Home e Away.
        WHEN n.market_id = 4 THEN
            IF(n.outcome_side = 'Home',
               j.goals_home + n.line_value > j.goals_away,
               j.goals_away - n.line_value > j.goals_home)
        WHEN n.market_id = 8 THEN
            IF(n.outcome_side = 'Yes',
               j.goals_home > 0 AND j.goals_away > 0,
               NOT (j.goals_home > 0 AND j.goals_away > 0))
        -- O modelo de premissas da DC só emite '1X' e 'X2'; o ELSE é sempre 'X2'. As
        -- linhas de '12' existem nas odds, não têm premissa e caem no JOIN — uma saída
        -- inteira fora da medição. Reportado, não corrigido.
        WHEN n.market_id = 12 THEN
            IF(n.outcome_side = '1X',
               j.goals_home >= j.goals_away,
               j.goals_away >= j.goals_home)
    END
 AS ganhou
    FROM normalizado n
    JOIN jogos j ON j.fixture_id = n.fixture_id
    WHERE COALESCE(n.porta_saida_catalogada, FALSE)
      AND COALESCE(n.porta_cobertura_pinnacle, FALSE)
      AND n.prob_justa_fechamento IS NOT NULL
      AND COALESCE(n.n_casas >= 4, FALSE)
      AND NOT COALESCE(n.pen_odd_outlier, TRUE)
      AND n.best_odd IS NOT NULL
      AND CASE
              WHEN n.market = 'double_chance'
                  THEN n.best_odd BETWEEN 1.25
                                      AND 2.0
              ELSE     n.best_odd BETWEEN 1.5
                                      AND 4.0
          END
      -- linha meia só onde a linha existe (AH e Gols); 1X2/BTTS/DC não têm linha.
      AND (n.line_value IS NULL OR (MOD(CAST(ROUND(ABS(n.line_value) * 4) AS INT64), 4) = 2))
),

com_lucro AS (
    SELECT
        *,
        IF(ganhou, best_odd, 0) - 1 AS lucro,
        -- os dois lados sem lado apostado saem das restrições e vão para o bloco 4.
        (lado IN ('Draw', 'Pick')) AS sem_lado_apostado
    FROM publicavel
),grade AS (
    SELECT
        '20/50' AS par,
        20 AS b, 50 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 50 THEN 'Alta'
             WHEN score_normalizado >= 20 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '25/55' AS par,
        25 AS b, 55 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 55 THEN 'Alta'
             WHEN score_normalizado >= 25 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '25/60' AS par,
        25 AS b, 60 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 60 THEN 'Alta'
             WHEN score_normalizado >= 25 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '30/60' AS par,
        30 AS b, 60 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 60 THEN 'Alta'
             WHEN score_normalizado >= 30 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '33/67' AS par,
        33 AS b, 67 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 67 THEN 'Alta'
             WHEN score_normalizado >= 33 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '35/65' AS par,
        35 AS b, 65 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 65 THEN 'Alta'
             WHEN score_normalizado >= 35 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '40/70' AS par,
        40 AS b, 70 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 70 THEN 'Alta'
             WHEN score_normalizado >= 40 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
    UNION ALL
    SELECT
        '50/75' AS par,
        50 AS b, 75 AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= 75 THEN 'Alta'
             WHEN score_normalizado >= 50 THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    -- ⚠️ `score_normalizado IS NOT NULL` é EXPLÍCITO, e não confiança no `ELSE`. O CASE das
    -- faixas termina em `ELSE 'Baixa'`, então uma nota NULL — linha sem premissa avaliável —
    -- cairia na `Baixa` sem carimbo nenhum, e "não pôde ser avaliada" viraria "foi avaliada
    -- e tirou pouco", que é a confusão que a ADR 0003 existe para impedir. Medido nesta
    -- rodada: ZERO linhas nulas na população publicável, nos cinco mercados. O filtro não
    -- muda número nenhum hoje; ele existe para o dia em que mudar, e o bloco 0 conta quantas
    -- ele tirou para que o zero seja LIDO em vez de suposto.
    FROM com_lucro WHERE NOT sem_lado_apostado AND score_normalizado IS NOT NULL
),

grade_media AS (
    SELECT g.*, AVG(lucro) OVER (PARTITION BY par, faixa) AS media_faixa
    FROM grade g
),
grade_por_fixture AS (
    SELECT par, faixa, fixture_id, SUM(lucro - media_faixa) AS resid_jogo
    FROM grade_media GROUP BY 1, 2, 3
),
grade_erro AS (
    SELECT par, faixa, SUM(POW(resid_jogo, 2)) AS soma_quad, COUNT(*) AS n_jogos
    FROM grade_por_fixture GROUP BY 1, 2
),
grade_faixa AS (
    SELECT
        g.par, ANY_VALUE(g.b) AS b, ANY_VALUE(g.a) AS a, g.faixa,
        COUNT(*)                                                   AS n_apostas,
        ANY_VALUE(e.n_jogos)                                       AS n_jogos,
        ROUND(AVG(g.lucro) * 100, 1)                               AS roi,
        ROUND(SAFE_DIVIDE(SQRT(ANY_VALUE(e.soma_quad)), COUNT(*)) * 100, 1) AS ep_cluster,
        ROUND(COUNT(*) * 100.0
              / SUM(COUNT(*)) OVER (PARTITION BY g.par), 1)        AS share_pct
    FROM grade_media g
    JOIN grade_erro e USING (par, faixa)
    GROUP BY g.par, g.faixa
),lados_do_seed AS (
    SELECT market, lado
    FROM `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto`
    WHERE p95 > 0
),
grade_c3 AS (
    SELECT
        p.par,
        MIN(COALESCE(o.n_faixas_no_lado, 0)) = 3 AS c3_ok
    FROM (SELECT DISTINCT par FROM grade) p
    CROSS JOIN lados_do_seed s
    LEFT JOIN (
        SELECT par, market, lado, COUNT(DISTINCT faixa) AS n_faixas_no_lado
        FROM grade GROUP BY 1, 2, 3
    ) o
      ON o.par = p.par AND o.market = s.market AND o.lado = s.lado
    GROUP BY p.par
),

grade_veredito AS (
    SELECT
        f.par,
        ANY_VALUE(f.b) AS b, ANY_VALUE(f.a) AS a,
        MIN(f.share_pct)                          AS menor_share,
        MAX(f.share_pct)                          AS maior_share,
        MIN(f.share_pct) >= 10                    AS c1_ok,
        MAX(f.share_pct) <= 65                    AS c2_ok,
        ANY_VALUE(c3.c3_ok)                       AS c3_ok,
        MAX(IF(f.faixa = 'Alta',  f.roi, NULL))
          - MAX(IF(f.faixa = 'Baixa', f.roi, NULL)) AS gap_roi,
        MAX(IF(f.faixa = 'Alta',  f.ep_cluster, NULL)) AS ep_alta,
        MAX(IF(f.faixa = 'Baixa', f.ep_cluster, NULL)) AS ep_baixa
    FROM grade_faixa f
    JOIN grade_c3 c3 USING (par)
    GROUP BY f.par
),

bloco1 AS (
    SELECT
        '1. GRADE' AS bloco,
        v.par AS chave, f.faixa AS sub,
        f.n_apostas, f.n_jogos, f.share_pct, f.roi, f.ep_cluster,
        v.gap_roi,
        CASE WHEN NOT v.c1_ok THEN 'reprova C1 (faixa < 10%)'
             WHEN NOT v.c2_ok THEN 'reprova C2 (faixa > 65%)'
             WHEN NOT v.c3_ok THEN 'reprova C3 (lado com faixa vazia)'
             ELSE                  'passa C1-C3' END AS veredito
    FROM grade_veredito v
    JOIN grade_faixa f USING (par)
),grade_discrimina AS (
    SELECT
        *,
        SQRT(POW(ep_alta, 2) + POW(ep_baixa, 2)) AS ep_gap,
        ABS(gap_roi) > SQRT(POW(ep_alta, 2) + POW(ep_baixa, 2)) AS discrimina
    FROM grade_veredito
    WHERE c1_ok AND c2_ok AND c3_ok
),

ramo AS (
    SELECT
        COUNT(*)                         AS n_pares_validos,
        COUNTIF(discrimina)              AS n_discriminam,
        -- E2: nenhum par passa nas restrições -> nada é proposto.
        -- E1: nenhum par discrimina        -> cai para o melhor equilíbrio.
        CASE WHEN COUNT(*) = 0        THEN 'E2 - nenhum par satisfaz C1-C3: NADA e proposto, a questao vai ao PM'
             WHEN COUNTIF(discrimina) = 0 THEN 'E1 - o objetivo nao discrimina: escolha por EQUILIBRIO'
             ELSE                          'PRINCIPAL - maior gap de ROI entre Alta e Baixa'
        END AS ramo_aplicado
    FROM grade_discrimina
),

escolhido AS (
    SELECT d.par, d.b, d.a
    FROM grade_discrimina d
    CROSS JOIN ramo r
    ORDER BY
        -- no ramo principal manda o gap; no E1 ele é ignorado e manda o equilíbrio
        -- (menor faixa máxima). O desempate é o mesmo nos dois: par mais redondo, menor B.
        CASE WHEN r.n_discriminam > 0 THEN d.gap_roi      ELSE NULL END DESC,
        CASE WHEN r.n_discriminam = 0 THEN d.maior_share  ELSE NULL END ASC,
        (MOD(d.b, 5) + MOD(d.a, 5)) ASC,
        d.b ASC
    LIMIT 1
),

bloco0 AS (
    SELECT
        '0. RAMO DA REGRA' AS bloco,
        r.ramo_aplicado AS chave,
        (SELECT par FROM escolhido) AS sub,
        r.n_pares_validos AS n_apostas,
        r.n_discriminam   AS n_jogos,
        CAST(NULL AS FLOAT64) AS share_pct,
        CAST(NULL AS FLOAT64) AS roi,
        CAST(NULL AS FLOAT64) AS ep_cluster,
        CAST(NULL AS FLOAT64) AS gap_roi,
        'pares que passam C1-C3 = ' || CAST(r.n_pares_validos AS STRING)
          || ' | discriminam = ' || CAST(r.n_discriminam AS STRING)
          || ' | linhas com nota NULA excluidas = '
          || CAST((SELECT COUNT(*) FROM com_lucro
                   WHERE NOT sem_lado_apostado AND score_normalizado IS NULL) AS STRING)
          AS veredito
    FROM ramo r
),

bloco2 AS (
    SELECT
        '2. CURVA (par escolhido)' AS bloco,
        f.par AS chave, f.faixa AS sub,
        f.n_apostas, f.n_jogos, f.share_pct, f.roi, f.ep_cluster,
        CAST(NULL AS FLOAT64) AS gap_roi,
        CAST(NULL AS STRING)  AS veredito
    FROM grade_faixa f
    JOIN escolhido e USING (par)
),bloco3 AS (
    SELECT
        '3. LADOS' AS bloco,
        c.market || '/' || c.lado AS chave,
        CAST(NULL AS STRING) AS sub,
        COUNT(*)                                    AS n_apostas,
        COUNT(DISTINCT c.fixture_id)                AS n_jogos,
        CAST(NULL AS FLOAT64)                       AS share_pct,
        ROUND(AVG(c.lucro) * 100, 1)                AS roi,
        CAST(NULL AS FLOAT64)                       AS ep_cluster,
        CAST(NULL AS FLOAT64)                       AS gap_roi,
        'nota media ' || CAST(ROUND(AVG(c.score_normalizado), 1) AS STRING)
          || ' | p10 ' || CAST(APPROX_QUANTILES(c.score_normalizado, 10)[OFFSET(1)] AS STRING)
          || ' | mediana ' || CAST(APPROX_QUANTILES(c.score_normalizado, 10)[OFFSET(5)] AS STRING)
          || ' | p90 ' || CAST(APPROX_QUANTILES(c.score_normalizado, 10)[OFFSET(9)] AS STRING)
          AS veredito
    FROM com_lucro c
    WHERE NOT c.sem_lado_apostado
    GROUP BY 1, 2, 3
),

bloco4 AS (
    SELECT
        '4. SEM LADO APOSTADO (fora das restricoes)' AS bloco,
        c.market || '/' || c.lado AS chave,
        CAST(NULL AS STRING) AS sub,
        COUNT(*)                     AS n_apostas,
        COUNT(DISTINCT c.fixture_id) AS n_jogos,
        CAST(NULL AS FLOAT64)        AS share_pct,
        ROUND(AVG(c.lucro) * 100, 1) AS roi,
        CAST(NULL AS FLOAT64)        AS ep_cluster,
        CAST(NULL AS FLOAT64)        AS gap_roi,
        'nota sempre 0 por construcao' AS veredito
    FROM com_lucro c
    WHERE c.sem_lado_apostado
    GROUP BY 1, 2, 3
)

SELECT * FROM bloco0
UNION ALL SELECT * FROM bloco1
UNION ALL SELECT * FROM bloco2
UNION ALL SELECT * FROM bloco3
UNION ALL SELECT * FROM bloco4
ORDER BY bloco, chave, sub