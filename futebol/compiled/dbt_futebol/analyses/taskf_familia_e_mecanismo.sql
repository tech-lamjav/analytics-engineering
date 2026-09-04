/*
    [F-4] O EFEITO DO EIXO DE ESCOPO QUEBRADO POR FAMÍLIA DE COMPETIÇÃO — e, antes disso, a prova
    de quais famílias sequer têm amostra na janela congelada.

    A #53 pede o efeito separado em `ano_calendario` e `split_year` (spec #49, user story 12). A
    razão é que na JANELA MEDIDA as duas se comportam de maneira diferente sob o eixo de escopo:
    numa split-year o rótulo de `season` vira no meio do ano, e como o eixo de escopo não toca o
    filtro `l.season = a.season`, o histórico doméstico do time continua cortado — só a célula
    `ambos` o alcança. A classificação é derivada do calendário pela macro
    taskf_familia_competicao(); o critério e as armadilhas dele estão no cabeçalho de lá.

    ⚠️ ANTES DE LER O EFEITO, LEIA A COMPOSIÇÃO. "Efeito nulo numa família" e "família sem
    amostra" são coisas diferentes e a segunda é a que se espera aqui: a #51 já mediu que os
    únicos jogos de Champions da janela são os 8 de 04/08 à noite, que o teto do universo
    congelado remove. Uma célula vazia da quebra tem de ser lida como SEM AMOSTRA, nunca como
    "juntar campeonato não muda nada para as europeias" — a janela congelada (16/06 a 04/08) cai
    inteira na virada de temporada, e é por isso que ela é o pior lugar possível para medir
    split-year. As linhas de competição fora do universo saem com `jogos_no_universo = 0` de
    propósito: a ausência é o achado, e escondê-la faria a quebra parecer completa.

    ────────────────────────────────────────────────────────────────────────────────
    TRÊS COISAS NA MESMA SAÍDA, com a coluna `nivel` separando os grãos:

      nivel = 'competicao'  uma linha por competição EXISTENTE (as 13, não só as do universo),
                            com a família e a evidência que a classificou ao lado.
      nivel = 'familia'     o rollup por família.
      nivel = 'total'       o universo inteiro, que serve de denominador e de conferência.

    Somar linhas de níveis diferentes conta o mesmo jogo duas vezes — filtre `nivel` sempre.

    O MECANISMO é medido no carimbo por célula (`taskf_pit_por_celula`), não em `apostas`: são as
    partidas anteriores que cada par (jogo, time) ganhou ao soltar a competição. `min_jogos` do
    jogo é o MENOR `played_total` entre os dois times — a mesma definição do task01_base(), porque
    as premissas comparam os dois lados. As contagens de piso mostram quantos jogos do universo
    passam a satisfazer cada corte da varredura com o histórico junto (user story 5 da spec).

    ⚠️ De onde vem cada metade. O UNIVERSO (quais jogos e quais linhas de aposta) sai do
    task01_base() sobre a camada de premissas MATERIALIZADA AGORA, então esta análise deve rodar
    com as duas células já carimbadas — a corrente é a última que rodou. O EFEITO sai do carimbo,
    que tem as duas células gravadas e não depende de qual está materializada. Que o universo seja
    idêntico nas quatro células é invariante da Costura B (#55); aqui ele é reportado
    (`jogos_no_universo`) e tem de bater com as duas linhas correspondentes do `taskf_teste2`.

    COMO RODAR (do dbt_futebol/), depois de as DUAS células terem sido carimbadas:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_familia_e_mecanismo
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_familia_e_mecanismo.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/WITH jogos_encerrados AS (
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



fam_por_temporada AS (
    SELECT
        competition_id,
        competition,
        season,
        COUNT(*)          AS n_fixtures,
        MIN(kickoff_utc)  AS primeiro_kickoff,
        MAX(kickoff_utc)  AS ultimo_kickoff,
        EXTRACT(YEAR FROM MAX(kickoff_utc)) > EXTRACT(YEAR FROM MIN(kickoff_utc))
                          AS atravessa_a_virada
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    GROUP BY competition_id, competition, season
),

familia_competicao AS (
    SELECT
        competition,
        MIN(competition_id)               AS competition_id,
        COUNT(DISTINCT competition_id)    AS n_competition_ids,
        IF(LOGICAL_OR(atravessa_a_virada), 'split_year', 'ano_calendario') AS familia,
        COUNT(DISTINCT season)      AS temporadas_observadas,
        COUNT(DISTINCT IF(atravessa_a_virada, season, NULL)) AS temporadas_atravessando,
        SUM(n_fixtures)             AS fixtures_observados,
        MIN(primeiro_kickoff)       AS primeiro_kickoff,
        MAX(ultimo_kickoff)         AS ultimo_kickoff
    FROM fam_por_temporada
    GROUP BY competition
)

,

apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE (kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00'))
),

universo_por_competicao AS (
    SELECT
        competition,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*)                   AS linhas_no_universo
    FROM apostas_congeladas
    GROUP BY competition
),

fixtures_do_universo AS (
    SELECT DISTINCT fixture_id FROM apostas_congeladas
),pares AS (
    SELECT
        b.fixture_id,
        b.team_id,
        b.competition,
        b.played_total AS played_base,
        e.played_total AS played_escopo
    FROM (SELECT * FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula` WHERE celula = 'base')   AS b
    JOIN (SELECT * FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula` WHERE celula = 'escopo') AS e
      USING (fixture_id, team_id)
    JOIN fixtures_do_universo USING (fixture_id)
),

por_fixture AS (
    SELECT
        fixture_id,
        ANY_VALUE(competition) AS competition,
        MIN(played_base)       AS min_jogos_base,
        MIN(played_escopo)     AS min_jogos_escopo
    FROM pares
    GROUP BY fixture_id
),

mecanismo_por_competicao AS (
    SELECT
        competition,
        COUNT(*)                                     AS pares,
        COUNTIF(played_escopo > played_base)         AS pares_com_ganho,
        SUM(played_escopo - played_base)             AS soma_do_ganho,
        MAX(played_escopo - played_base)             AS ganho_max
    FROM pares
    GROUP BY competition
),

piso_por_competicao AS (
    SELECT
        competition,
        COUNTIF(min_jogos_base   >= 3)      AS jogos_min3_base,
        COUNTIF(min_jogos_escopo >= 3)      AS jogos_min3_escopo,
        COUNTIF(min_jogos_base <  3
                AND min_jogos_escopo >= 3)  AS jogos_cruzam_piso3,
        COUNTIF(min_jogos_base   >= 5)      AS jogos_min5_base,
        COUNTIF(min_jogos_escopo >= 5)      AS jogos_min5_escopo,
        COUNTIF(min_jogos_base <  5
                AND min_jogos_escopo >= 5)  AS jogos_cruzam_piso5,
        COUNTIF(min_jogos_base   >= 10)      AS jogos_min10_base,
        COUNTIF(min_jogos_escopo >= 10)      AS jogos_min10_escopo,
        COUNTIF(min_jogos_base <  10
                AND min_jogos_escopo >= 10)  AS jogos_cruzam_piso10
    FROM por_fixture
    GROUP BY competition
),por_competicao AS (
    SELECT
        f.competition,
        f.competition_id,
        f.n_competition_ids,
        f.familia,
        f.temporadas_observadas,
        f.temporadas_atravessando,
        DATE(f.primeiro_kickoff)                 AS primeiro_kickoff,
        DATE(f.ultimo_kickoff)                   AS ultimo_kickoff,
        COALESCE(u.jogos_no_universo, 0)         AS jogos_no_universo,
        COALESCE(u.linhas_no_universo, 0)        AS linhas_no_universo,
        COALESCE(m.pares, 0)                     AS pares,
        COALESCE(m.pares_com_ganho, 0)           AS pares_com_ganho,
        COALESCE(m.soma_do_ganho, 0)             AS soma_do_ganho,
        m.ganho_max                              AS ganho_max,
        COALESCE(p.jogos_min3_base, 0)     AS jogos_min3_base,
        COALESCE(p.jogos_min3_escopo, 0)   AS jogos_min3_escopo,
        COALESCE(p.jogos_cruzam_piso3, 0)  AS jogos_cruzam_piso3,
        COALESCE(p.jogos_min5_base, 0)     AS jogos_min5_base,
        COALESCE(p.jogos_min5_escopo, 0)   AS jogos_min5_escopo,
        COALESCE(p.jogos_cruzam_piso5, 0)  AS jogos_cruzam_piso5,
        COALESCE(p.jogos_min10_base, 0)     AS jogos_min10_base,
        COALESCE(p.jogos_min10_escopo, 0)   AS jogos_min10_escopo,
        COALESCE(p.jogos_cruzam_piso10, 0)  AS jogos_cruzam_piso10
    FROM familia_competicao       AS f
    LEFT JOIN universo_por_competicao  AS u USING (competition)
    LEFT JOIN mecanismo_por_competicao AS m USING (competition)
    LEFT JOIN piso_por_competicao      AS p USING (competition)
),

empilhado AS (
    SELECT
        'competicao' AS nivel, 1 AS nivel_ord, competition AS chave, familia,
        competition_id, n_competition_ids, temporadas_observadas, temporadas_atravessando,
        primeiro_kickoff, ultimo_kickoff,
        jogos_no_universo, linhas_no_universo, pares, pares_com_ganho, soma_do_ganho, ganho_max,
        jogos_min3_base, jogos_min3_escopo, jogos_cruzam_piso3,
        jogos_min5_base, jogos_min5_escopo, jogos_cruzam_piso5,
        jogos_min10_base, jogos_min10_escopo, jogos_cruzam_piso10
    FROM por_competicao

    UNION ALL
    SELECT
        'familia', 2, familia AS chave, familia,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS DATE),  CAST(NULL AS DATE),
        
        SUM(jogos_no_universo)   AS jogos_no_universo,
        SUM(linhas_no_universo)  AS linhas_no_universo,
        SUM(pares)               AS pares,
        SUM(pares_com_ganho)     AS pares_com_ganho,
        SUM(soma_do_ganho)       AS soma_do_ganho,
        MAX(ganho_max)           AS ganho_max,
        SUM(jogos_min3_base)    AS jogos_min3_base,
        SUM(jogos_min3_escopo)  AS jogos_min3_escopo,
        SUM(jogos_cruzam_piso3) AS jogos_cruzam_piso3,
        SUM(jogos_min5_base)    AS jogos_min5_base,
        SUM(jogos_min5_escopo)  AS jogos_min5_escopo,
        SUM(jogos_cruzam_piso5) AS jogos_cruzam_piso5,
        SUM(jogos_min10_base)    AS jogos_min10_base,
        SUM(jogos_min10_escopo)  AS jogos_min10_escopo,
        SUM(jogos_cruzam_piso10) AS jogos_cruzam_piso10
    FROM por_competicao
    GROUP BY familia

    UNION ALL

    SELECT
        'total', 3, 'TODAS', CAST(NULL AS STRING),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS DATE),  CAST(NULL AS DATE),
        
        SUM(jogos_no_universo)   AS jogos_no_universo,
        SUM(linhas_no_universo)  AS linhas_no_universo,
        SUM(pares)               AS pares,
        SUM(pares_com_ganho)     AS pares_com_ganho,
        SUM(soma_do_ganho)       AS soma_do_ganho,
        MAX(ganho_max)           AS ganho_max,
        SUM(jogos_min3_base)    AS jogos_min3_base,
        SUM(jogos_min3_escopo)  AS jogos_min3_escopo,
        SUM(jogos_cruzam_piso3) AS jogos_cruzam_piso3,
        SUM(jogos_min5_base)    AS jogos_min5_base,
        SUM(jogos_min5_escopo)  AS jogos_min5_escopo,
        SUM(jogos_cruzam_piso5) AS jogos_cruzam_piso5,
        SUM(jogos_min10_base)    AS jogos_min10_base,
        SUM(jogos_min10_escopo)  AS jogos_min10_escopo,
        SUM(jogos_cruzam_piso10) AS jogos_cruzam_piso10
    FROM por_competicao
)

SELECT
    nivel,
    chave,
    familia,
    competition_id,
    n_competition_ids,
    temporadas_observadas,
    temporadas_atravessando,
    primeiro_kickoff,
    ultimo_kickoff,
    jogos_no_universo,
    ROUND(SAFE_DIVIDE(jogos_no_universo,
                      SUM(IF(nivel = 'total', jogos_no_universo, 0)) OVER ()) * 100, 1)
                                                              AS pct_do_universo,
    linhas_no_universo,
    pares,
    pares_com_ganho,
    ROUND(SAFE_DIVIDE(pares_com_ganho, pares) * 100, 1)       AS pct_pares_com_ganho,
    ROUND(SAFE_DIVIDE(soma_do_ganho, pares), 2)               AS ganho_medio_por_par,
    ganho_max,
    jogos_min3_base,
    jogos_min3_escopo,
    jogos_cruzam_piso3,
    jogos_min5_base,
    jogos_min5_escopo,
    jogos_cruzam_piso5,
    jogos_min10_base,
    jogos_min10_escopo,
    jogos_cruzam_piso10
FROM empilhado
ORDER BY nivel_ord, jogos_no_universo DESC, chave