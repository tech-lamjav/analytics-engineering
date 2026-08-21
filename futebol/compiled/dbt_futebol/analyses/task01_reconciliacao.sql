

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
      AND DATE(kickoff_utc) <= DATE('2026-08-02')
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
        STRUCT('linha_subindo' AS premissa, p.linha_subindo AS acesa),
        STRUCT('defesas_firmes' AS premissa, p.defesas_firmes AS acesa),
        STRUCT('clean_sheets_altos' AS premissa, p.clean_sheets_altos AS acesa),
        STRUCT('xg_baixo_combinado' AS premissa, p.xg_baixo_combinado AS acesa),
        STRUCT('ataques_fracos' AS premissa, p.ataques_fracos AS acesa),
        STRUCT('historico_under' AS premissa, p.historico_under AS acesa),
        STRUCT('linha_descendo' AS premissa, p.linha_descendo AS acesa)
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
        LEAST(COALESCE(h.played_total, 0), COALESCE(a.played_total, 0)) AS min_jogos
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
     OR MOD(CAST(ABS(o.line_value) * 2 AS INT64), 2) = 1)

)

,teste3 AS (
    SELECT 'Teste 3' AS bloco, 'a. universo sem porta' AS metrica,
           COUNT(*) AS n, -10.2 AS esperado,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM apostas

    UNION ALL
    SELECT 'Teste 3', 'b. 2+ premissas',
           COUNT(*), -7.6,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE n_prem >= 2

    UNION ALL
    SELECT 'Teste 3', 'c. 3+ premissas',
           COUNT(*), -6.0,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE n_prem >= 3

    UNION ALL
    SELECT 'Teste 3', 'd. regra de hoje (edge > 0)',
           COUNT(*), -12.3,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE edge > 0

    UNION ALL
    SELECT 'Teste 3', 'e. edge > 0 e 2+ premissas',
           COUNT(*), -15.4,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE edge > 0 AND n_prem >= 2
),teste3_mercado AS (
    SELECT
        'Teste 3 por mercado (2+)' AS bloco,
        m.rotulo AS metrica,
        COUNT(*) AS n,
        ANY_VALUE(m.esperado) AS esperado,
        ROUND((SUM(IF(a.ganhou, a.best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM apostas AS a
    JOIN UNNEST([
        STRUCT(1  AS market_id, 'a. 1X2'          AS rotulo, -2.5 AS esperado),
        STRUCT(5  AS market_id, 'b. Gols'         AS rotulo, -7.3 AS esperado),
        STRUCT(4  AS market_id, 'c. Handicap'     AS rotulo, -9.9 AS esperado),
        STRUCT(8  AS market_id, 'd. BTTS'         AS rotulo, -1.1 AS esperado),
        STRUCT(12 AS market_id, 'e. Dupla Chance' AS rotulo,  1.4 AS esperado)
    ]) AS m
      ON m.market_id = a.market_id
    WHERE a.n_prem >= 2
    GROUP BY m.rotulo
),teste2_gols AS (
    SELECT
        'Teste 2 (Gols)' AS bloco,
        pl.premissa      AS metrica,
        COUNTIF(pl.acesa) AS n,
        e.esperado,
        ROUND((AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL))
             - AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL))) * 100, 1) AS obtido
    FROM apostas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    JOIN UNNEST([
        STRUCT('clean_sheets_altos' AS premissa,  16.9 AS esperado),
        STRUCT('defesas_firmes'     AS premissa,   3.4 AS esperado),
        STRUCT('xg_combinado_alto'  AS premissa,  -2.6 AS esperado),
        STRUCT('ataque_combinado'   AS premissa,  -3.6 AS esperado),
        STRUCT('defesas_vazaveis'   AS premissa,  -5.2 AS esperado),
        STRUCT('ambos_vazam'        AS premissa,  -3.7 AS esperado)
    ]) AS e
      ON e.premissa = pl.premissa
    WHERE a.market_id = 5
      AND a.benchmark = 'sharp'
    GROUP BY 1, 2, 4
),

cobertura AS (
    SELECT 'Cobertura' AS bloco,
           'a. jogos que sobreviveram a todos os recortes' AS metrica,
           COUNT(*) AS n, 168.0 AS esperado,
           CAST(COUNT(DISTINCT fixture_id) AS FLOAT64) AS obtido
    FROM apostas

    -- Se isto não for zero, a degradação graciosa falhou em algum lugar: contar
    -- premissas por SUM(CAST(bool AS INT64)) (a query original) propaga NULL e derruba
    -- a linha inteira de toda porta, enquanto COUNTIF não. Aí o número publicado não é
    -- reproduzível por construção, e não por erro meu.
    UNION ALL
    SELECT 'Cobertura', 'b. linhas com premissa NULL',
           COUNT(*), 0.0,
           CAST(SUM(n_prem_null) AS FLOAT64)
    FROM apostas
),descartes AS (
    SELECT
        CASE
            WHEN o.market_id NOT IN (1, 5, 4, 8, 12)
                THEN 'a. fora do escopo do Motor (declarado)'
            WHEN o.best_odd IS NULL OR o.edge IS NULL
                THEN 'b. sem preco justo, edge NULL (declarado)'
            WHEN NOT 
    (o.market_id NOT IN (4, 5)
     OR MOD(CAST(ABS(o.line_value) * 2 AS INT64), 2) = 1)

                THEN 'c. linha inteira, push possivel (declarado)'
            WHEN o.market_id = 12 AND o.outcome_side = '12'
                THEN 'd. gap conhecido: DC nao emite premissa p/ 12'
            ELSE
                 'e. INESPERADO'
        END AS motivo
    FROM odds AS o
    JOIN jogos_encerrados AS j
      ON j.fixture_id = o.fixture_id
    LEFT JOIN apostas AS ap
      ON  ap.market_id                  = o.market_id
      AND ap.fixture_id                 = o.fixture_id
      AND ap.outcome_side               = o.outcome_side
      AND COALESCE(ap.line_value, -999) = COALESCE(o.line_value, -999)
    WHERE ap.fixture_id IS NULL
),

descarte_assercao AS (
    SELECT 'Descarte' AS bloco,
           'z. INESPERADOS (tem de ser 0)' AS metrica,
           COUNT(*) AS n,
           0.0 AS esperado,
           CAST(COUNTIF(motivo = 'e. INESPERADO') AS FLOAT64) AS obtido
    FROM descartes
),

descarte_detalhe AS (
    SELECT 'Descarte' AS bloco, motivo AS metrica,
           COUNT(*) AS n, CAST(NULL AS FLOAT64) AS esperado,
           CAST(COUNT(*) AS FLOAT64) AS obtido
    FROM descartes GROUP BY motivo
),por_benchmark AS (
    SELECT
        'Cobertura por benchmark' AS bloco,
        CONCAT('market ', CAST(market_id AS STRING), ' — ', benchmark) AS metrica,
        COUNT(*) AS n,
        CAST(NULL AS FLOAT64) AS esperado,
        ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM apostas
    GROUP BY market_id, benchmark
)

SELECT
    bloco,
    metrica,
    n,
    esperado,
    obtido,
    ROUND(obtido - esperado, 1) AS delta,
    -- 0,05 é tolerância de ARREDONDAMENTO e nada mais: os valores publicados têm 1 casa
    -- decimal, então reprodução exata dá delta 0,0. Não há faixa intermediária de
    -- propósito — uma banda larga o bastante p/ acomodar "quase igual" teria engolido a
    -- deriva de 0,4pp do Gols, que é o achado do ticket.
    CASE
        WHEN esperado IS NULL              THEN '—'
        WHEN ABS(obtido - esperado) < 0.05 THEN 'OK'
        ELSE                                    'DIVERGE'
    END AS status
FROM (
    SELECT * FROM teste3
    UNION ALL SELECT * FROM teste3_mercado
    UNION ALL SELECT * FROM teste2_gols
    UNION ALL SELECT * FROM cobertura
    UNION ALL SELECT * FROM descarte_assercao
    UNION ALL SELECT * FROM descarte_detalhe
    UNION ALL SELECT * FROM por_benchmark
)
ORDER BY bloco, metrica