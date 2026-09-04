WITH jogos_encerrados AS (
    SELECT
        fixture_id,
        competition,
        season,
        home_team_id,
        away_team_id,
        kickoff_utc,
        goals_home,
        goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
),odds AS (
    SELECT
        fixture_id,
        market_id,
        outcome_side,
        line_value,
        best_odd,
        edge,
        n_casas,
        n_outcomes_valor,
        prob_justa_fechamento,
        valor_fonte,
        penalidades_globais_pts,
        CASE
            WHEN market_id = 12           THEN 'derivada'
            WHEN valor_fonte = 'pinnacle' THEN 'sharp'
            ELSE valor_fonte
        END AS benchmark,
        -- ⚠️ Conjunto de saídas INCOMPLETO: só um lado da linha foi precificado. O
        -- de-vig de consenso normaliza sobre o conjunto, então com um único outcome ele
        -- devolve prob_justa = 1,0 — certeza — e o edge vira `odd − 1`. Uma odd de 150
        -- aparece como "edge de 14.900%".
        --
        -- Medido no universo de análise: 172 linhas, TODAS consenso, 2 vitórias em 172,
        -- ROI −35,5%. É o pior lugar possível para um erro de sinal — o Motor diz valor
        -- máximo onde o acerto real é 1,2%.
        --
        -- PRODUÇÃO NUNCA FOI AFETADA: o gate do mart exige conjunto Pinnacle completo e
        -- prob justa não-nula. (Correção factual: o gate de liquidez é n_casas >= 3, não
        -- >= 4 — a proteção efetiva vinha do gate de COMPLETUDE, não do de liquidez.)
        --
        -- ⚠️ CORRIGIDO NA ORIGEM em 2026-08-05 (spec #22). O de-vig passou a exigir conjunto
        -- de saídas completo para emitir: as linhas degeneradas agora saem daqui pelo filtro
        -- de edge não-nulo que já existe, porque não têm mais edge. Este flag NÃO foi
        -- removido, mas TROCOU DE PAPEL — de "exposto para reproduzir o publicado" para
        -- TESTEMUNHA: se voltar a ser verdadeiro em alguma linha, a correção regrediu.
        -- Mantido também para que a próxima análise VEJA que esta exclusão existe, em vez
        -- de herdá-la em silêncio.
        COALESCE(n_outcomes_valor < 2, TRUE) AS conjunto_incompleto
    FROM (SELECT * EXCEPT (janela_prioridade, janela_e_corrente)
    FROM (SELECT
        d.* EXCEPT (_janela_prioridade, _line_key),
        d._janela_prioridade AS janela_prioridade,
        d._janela_prioridade = MAX(d._janela_prioridade) OVER (
            PARTITION BY d.fixture_id, d.market_id, d._line_key
        ) AS janela_e_corrente
    FROM (
        SELECT
            *,
            CASE janela_usada
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END AS _janela_prioridade,
            COALESCE(CAST(line_value AS STRING), 'NONE')    AS _line_key
        FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    ) d)
    WHERE janela_e_corrente)
),prem_long AS (
    SELECT
        1 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2` AS p
    CROSS JOIN UNNEST([
        STRUCT('forca_mismatch' AS premissa, p.forca_mismatch AS acesa),
        STRUCT('superioridade_xg' AS premissa, p.superioridade_xg AS acesa),
        STRUCT('mando' AS premissa, p.mando AS acesa),
        STRUCT('desfalque_adversario' AS premissa, p.desfalque_adversario AS acesa),
        STRUCT('superioridade_tabela' AS premissa, p.superioridade_tabela AS acesa),
        STRUCT('forma' AS premissa, p.forma AS acesa),
        STRUCT('h2h_favoravel' AS premissa, p.h2h_favoravel AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        5 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        p.line_value AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou` AS p
    CROSS JOIN UNNEST([
        STRUCT('ataque_combinado' AS premissa, p.ataque_combinado AS acesa),
        STRUCT('defesas_vazaveis' AS premissa, p.defesas_vazaveis AS acesa),
        STRUCT('xg_combinado_alto' AS premissa, p.xg_combinado_alto AS acesa),
        STRUCT('ritmo_alto' AS premissa, p.ritmo_alto AS acesa),
        STRUCT('ambos_vazam' AS premissa, p.ambos_vazam AS acesa),
        STRUCT('historico_over' AS premissa, p.historico_over AS acesa),
        STRUCT('defesas_firmes' AS premissa, p.defesas_firmes AS acesa),
        STRUCT('clean_sheets_altos' AS premissa, p.clean_sheets_altos AS acesa),
        STRUCT('xg_baixo_combinado' AS premissa, p.xg_baixo_combinado AS acesa),
        STRUCT('ataques_fracos' AS premissa, p.ataques_fracos AS acesa),
        STRUCT('historico_under' AS premissa, p.historico_under AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        4 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        p.line_value AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah` AS p
    CROSS JOIN UNNEST([
        STRUCT('supremacia' AS premissa, p.supremacia AS acesa),
        STRUCT('tende_golear' AS premissa, p.tende_golear AS acesa),
        STRUCT('adversario_fragil_fora' AS premissa, p.adversario_fragil_fora AS acesa),
        STRUCT('mando_forte' AS premissa, p.mando_forte AS acesa),
        STRUCT('sem_rodizio' AS premissa, p.sem_rodizio AS acesa),
        STRUCT('raramente_perde_por_2' AS premissa, p.raramente_perde_por_2 AS acesa),
        STRUCT('defesa_fora_solida' AS premissa, p.defesa_fora_solida AS acesa),
        STRUCT('favorito_irregular' AS premissa, p.favorito_irregular AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        8 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts` AS p
    CROSS JOIN UNNEST([
        STRUCT('ambos_marcam' AS premissa, p.ambos_marcam AS acesa),
        STRUCT('ataque_dos_dois' AS premissa, p.ataque_dos_dois AS acesa),
        STRUCT('defesas_vazaveis' AS premissa, p.defesas_vazaveis AS acesa),
        STRUCT('historico_btts' AS premissa, p.historico_btts AS acesa),
        STRUCT('defesa_forte' AS premissa, p.defesa_forte AS acesa),
        STRUCT('ataque_trava' AS premissa, p.ataque_trava AS acesa),
        STRUCT('historico_seco' AS premissa, p.historico_seco AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        12 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc` AS p
    CROSS JOIN UNNEST([
        STRUCT('lado_coberto_forte' AS premissa, p.lado_coberto_forte AS acesa),
        STRUCT('equilibrio_defensivo' AS premissa, p.equilibrio_defensivo AS acesa),
        STRUCT('adversario_limitado' AS premissa, p.adversario_limitado AS acesa),
        STRUCT('invicto_recente' AS premissa, p.invicto_recente AS acesa)
    ]) AS u
),prem_n AS (
    SELECT
        market_id,
        fixture_id,
        outcome_side,
        line_value,
        COUNTIF(acesa)         AS n_prem,
        COUNTIF(acesa IS NULL) AS n_prem_null
    FROM prem_long
    GROUP BY 1, 2, 3, 4
),prem_linha AS (
    SELECT
        1 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        penalidades_1x2_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
    UNION ALL
    SELECT
        5 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        line_value AS line_value,
        penalidades_ou_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou`
    UNION ALL
    SELECT
        4 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        line_value AS line_value,
        penalidades_ah_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
    UNION ALL
    SELECT
        8 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        penalidades_btts_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts`
    UNION ALL
    SELECT
        12 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        penalidades_dc_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
),pit AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total_disponivel, 0), COALESCE(a.played_total_disponivel, 0)) AS min_jogos
    FROM jogos_encerrados AS j
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS h
           ON h.fixture_id = j.fixture_id
          AND h.team_id    = j.home_team_id
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS a
           ON a.fixture_id = j.fixture_id
          AND a.team_id    = j.away_team_id
),

apostas AS (
    SELECT
        o.market_id,
        o.fixture_id,
        o.outcome_side,
        o.line_value,
        o.best_odd,
        o.edge,
        o.n_casas,
        o.prob_justa_fechamento,
        o.benchmark,
        o.conjunto_incompleto,
        j.competition,
        j.season,
        j.kickoff_utc,
        COALESCE(pit.min_jogos, 0) AS min_jogos,
        pn.n_prem,
        pn.n_prem_null,
        -- Insumos da composição "Score pós-A1" do Teste 4. A A1 remove o componente de
        -- VALOR da nota; corroboração e penalidades continuam. Nota: a corroboração
        -- hoje só está implementada p/ 1X2 e o /predictions era ~vazio no histórico,
        -- então ela é majoritariamente 0 — o que na prática torna o Score pós-A1
        -- ≈ nota de premissas menos penalidades.
        COALESCE(c.pts_corroboracao, 0)              AS pts_corroboracao,
        COALESCE(o.penalidades_globais_pts, 0)       AS penalidades_globais_pts,
        COALESCE(px.penalidades_especificas_pts, 0)  AS penalidades_especificas_pts,
        
    CASE
        WHEN o.market_id = 1 THEN
            CASE o.outcome_side
                WHEN 'Home' THEN j.goals_home > j.goals_away
                WHEN 'Away' THEN j.goals_away > j.goals_home
                ELSE             j.goals_home = j.goals_away
            END
        WHEN o.market_id = 5 THEN
            IF(o.outcome_side = 'Over',
               j.goals_home + j.goals_away > o.line_value,
               j.goals_home + j.goals_away < o.line_value)
        -- line_value vem na ÓTICA DO MANDANTE e é igual p/ Home e Away.
        WHEN o.market_id = 4 THEN
            IF(o.outcome_side = 'Home',
               j.goals_home + o.line_value > j.goals_away,
               j.goals_away - o.line_value > j.goals_home)
        WHEN o.market_id = 8 THEN
            IF(o.outcome_side = 'Yes',
               j.goals_home > 0 AND j.goals_away > 0,
               NOT (j.goals_home > 0 AND j.goals_away > 0))
        -- O modelo de premissas da DC só emite '1X' e 'X2'; o ELSE é sempre 'X2'. As
        -- linhas de '12' existem nas odds, não têm premissa e caem no JOIN — uma saída
        -- inteira fora da medição. Reportado, não corrigido.
        WHEN o.market_id = 12 THEN
            IF(o.outcome_side = '1X',
               j.goals_home >= j.goals_away,
               j.goals_away >= j.goals_home)
    END
 AS ganhou
    FROM odds AS o
    JOIN jogos_encerrados AS j
      ON j.fixture_id = o.fixture_id
    JOIN prem_n AS pn
      ON  pn.market_id                      = o.market_id
      AND pn.fixture_id                     = o.fixture_id
      AND pn.outcome_side                   = o.outcome_side
      AND COALESCE(pn.line_value, -999)     = COALESCE(o.line_value, -999)
    LEFT JOIN pit
      ON pit.fixture_id = o.fixture_id
    LEFT JOIN prem_linha AS px
      ON  px.market_id                  = o.market_id
      AND px.fixture_id                 = o.fixture_id
      AND px.outcome_side               = o.outcome_side
      AND COALESCE(px.line_value, -999) = COALESCE(o.line_value, -999)
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_corroboracao` AS c
      ON  c.market_id                  = o.market_id
      AND c.fixture_id                 = o.fixture_id
      AND c.outcome_side               = o.outcome_side
      AND COALESCE(c.line_value, -999) = COALESCE(o.line_value, -999)
    WHERE o.best_odd IS NOT NULL
      AND o.edge     IS NOT NULL
      -- Escopo do Motor, DECLARADO e derivado do catálogo de premissas acima — não
      -- digitado de novo. A coleta traz mercados que o Motor não pontua: 6 (Goals
      -- Over/Under First Half), 7 (HT/FT Double), 10 (Exact Score). Sem esta linha eles
      -- cairiam pelo INNER JOIN com prem_n, o que é correto por acidente: só do 6 são
      -- ~3,6 mil linhas sumindo em silêncio na janela congelada.
      AND o.market_id IN (1, 5, 4, 8, 12)
      AND 
    (o.market_id NOT IN (4, 5)
     OR (MOD(CAST(ROUND(ABS(o.line_value) * 4) AS INT64), 4) = 2))

)

,

validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

metades AS (
    SELECT fixture_id, NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM validas)
),

linhas AS (
    SELECT a.*, m.metade, pl.premissa, pl.acesa
    FROM validas AS a
    JOIN metades AS m USING (fixture_id)
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
),ganhos AS (
    SELECT
        0 AS piso, 'tudo' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= 0
      AND TRUE
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    UNION ALL
    SELECT
        0 AS piso, 'h1' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= 0
      AND metade = 1
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    UNION ALL
    SELECT
        5 AS piso, 'tudo' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= 5
      AND TRUE
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    UNION ALL
    SELECT
        5 AS piso, 'h1' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= 5
      AND metade = 1
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    UNION ALL
    SELECT
        10 AS piso, 'tudo' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= 10
      AND TRUE
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    UNION ALL
    SELECT
        10 AS piso, 'h1' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= 10
      AND metade = 1
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
),apostas_forte AS (
    SELECT
        l.fixture_id, l.market_id, l.outcome_side, l.line_value, l.metade, l.min_jogos,
        g.piso, g.janela,
        LOGICAL_OR(l.acesa AND g.ganho >= 5)       AS tem_forte,
        IF(ANY_VALUE(l.ganhou), ANY_VALUE(l.best_odd), 0) - 1 AS lucro
    FROM linhas AS l
    JOIN ganhos AS g
      ON g.market_id = l.market_id AND g.premissa = l.premissa
    WHERE l.min_jogos >= g.piso
    GROUP BY l.fixture_id, l.market_id, l.outcome_side, l.line_value,
             l.metade, l.min_jogos, g.piso, g.janela
),

cenarios AS (
    SELECT piso, '1. todas as apostas, 2a metade' AS cenario, lucro, fixture_id
    FROM apostas_forte WHERE janela = 'tudo' AND metade = 2

    UNION ALL
    SELECT piso, '2. forte de TODA a janela, ROI em toda (IN-SAMPLE)', lucro, fixture_id
    FROM apostas_forte WHERE janela = 'tudo' AND tem_forte

    UNION ALL
    SELECT piso, '3. forte de TODA a janela, ROI na 2a metade', lucro, fixture_id
    FROM apostas_forte WHERE janela = 'tudo' AND tem_forte AND metade = 2

    UNION ALL
    SELECT piso, '4. forte so da 1a metade, ROI na 2a (OUT-OF-SAMPLE)', lucro, fixture_id
    FROM apostas_forte WHERE janela = 'h1' AND tem_forte AND metade = 2
),

media AS (
    SELECT piso, cenario, AVG(lucro) AS m FROM cenarios GROUP BY piso, cenario
),
resid AS (
    SELECT c.piso, c.cenario, c.fixture_id, SUM(c.lucro - m.m) AS r
    FROM cenarios AS c JOIN media AS m USING (piso, cenario)
    GROUP BY 1, 2, 3
)

SELECT
    CONCAT('piso ', LPAD(CAST(c.piso AS STRING), 2, '0')) AS corte,
    c.cenario,
    COUNT(*)                                              AS n_apostas,
    COUNT(DISTINCT c.fixture_id)                          AS n_jogos,
    ROUND(AVG(c.lucro) * 100, 1)                          AS roi,
    -- erro-padrão agrupado por fixture
    ROUND(SAFE_DIVIDE(SQRT(ANY_VALUE(e.soma_quad)), COUNT(*)) * 100, 1) AS ep_cluster
FROM cenarios AS c
JOIN (SELECT piso, cenario, SUM(POW(r, 2)) AS soma_quad FROM resid GROUP BY 1, 2) AS e
  USING (piso, cenario)
GROUP BY c.piso, c.cenario
ORDER BY corte, cenario