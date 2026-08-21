/*
    [F-8] RODÍZIO DE ELENCO — o segundo confundidor do merge, com número em vez de opinião.

    O QUE ELE AMEAÇA. A célula `escopo` empresta ao histórico de um time as partidas que ele jogou
    em outra competição. Se o time entra em campo na copa com OUTRO elenco — poupando titulares
    para o campeonato —, essas partidas emprestadas descrevem um time que não vai jogar o jogo
    sobre o qual a premissa decide. O ganho de amostra seria real e a informação, não. O ticket de
    origem registrou a ressalva sem número; a spec #49 (user story 23) pediu o número.

    A MEDIDA. Para cada time, os jogos dele são postos em ordem de kickoff e cada par de jogos
    CONSECUTIVOS vira uma observação: quantos dos 11 titulares se repetiram. O par é classificado
    pelo tipo das duas competições (`dim_leagues.league_type`, derivado do catálogo):

      liga_liga   os dois jogos são de pontos corridos           → é o CONTROLE
      liga_copa   um de cada — é a pergunta do ticket            → é o TRATAMENTO
      copa_copa   os dois de copa

    ⚠️ SEM O CONTROLE, O NÚMERO DO TRATAMENTO NÃO QUER DIZER NADA. "7 dos 11 titulares se
    repetiram entre a liga e a copa" só é rodízio se entre dois jogos DE LIGA se repetirem 11 — e
    não se repetem: lesão, suspensão e desgaste mexem no XI o tempo todo. O que responde à
    pergunta do ticket é a DIFERENÇA entre os dois estratos, e é por isso que o controle é medido
    aqui dentro e não citado de memória.

    ⚠️ E O CONTROLE TEM UM CONFUNDIDOR PRÓPRIO: CALENDÁRIO. Par liga↔copa costuma ser jogo de
    meio de semana seguido de jogo de fim de semana, e par liga↔liga costuma ter uma semana
    inteira no meio. Rodízio por congestionamento e rodízio por prioridade de competição são
    coisas diferentes, e a segunda é a do ticket. Por isso a saída tem o nível
    `estrato_x_dias`, que corta os dois estratos pela distância entre os jogos: se a diferença
    entre `liga_copa` e `liga_liga` sobreviver DENTRO da mesma faixa de dias, ela não é
    calendário.

    ⚠️ A PREMISSA DO CRITÉRIO DE ACEITE É FALSA, E ISSO É RESULTADO. O ticket afirma que "a
    cobertura de lineups é de 100% em todas as competições". Não é — e falha exatamente onde o
    próprio ticket manda olhar, as fases iniciais da Copa do Brasil. O nível `cobertura` mede isso
    por competição, e nenhum lado sem XI utilizável entra num par: ele é contado e descartado, não
    completado. XI utilizável = exatamente 11 titulares na fase `real`.

    ⚠️ POR QUE A FASE `real`, E NÃO A ESCALAÇÃO INTEIRA. O `fact_fixture_lineups_players` dedupa
    por (fixture_id, player_id) com latest-wins, e não por (fixture_id, team_id, fase). Quando a
    escalação `confirmed` (~T-30min) e a `real` (pós-jogo) discordam sobre um jogador, as duas
    sobrevivem — uma por jogador — e o time aparece com 12 ou 13 "titulares". O custo do filtro
    não é afirmação de cabeçalho: o escopo `temporada_sem_filtro_de_fase` do nível `cobertura`
    repete a mesma contagem sem ele, e a diferença entre os dois escopos é o tamanho do artefato.
    O que sobra depois do filtro é falha de coleta, não dedup.

    ────────────────────────────────────────────────────────────────────────────────
    O UNIVERSO. Os times são os do universo congelado da [F] (a mesma macro do resto da task), e
    os jogos são os que a célula `escopo` teria para emprestar: mesma temporada das âncoras,
    kickoff antes do teto congelado, encerrados em `FT` — o mesmo filtro do
    `int_futebol_team_form_pit`, para o elenco medido ser o dos jogos que de fato entram na média.

    CINCO NÍVEIS NA MESMA SAÍDA, com a coluna `nivel` separando os grãos:

      cobertura       por (competição, escopo). `pool` são os lados que esta medição usa;
                      `temporada` são TODOS os lados encerrados da temporada dentro do teto, e é
                      ali que a afirmação de cobertura do ticket é conferida;
                      `temporada_sem_filtro_de_fase` é o mesmo sem o filtro `real`, e a diferença
                      para o anterior é o tamanho do artefato de dedup.
      total           por estrato, todos os times juntos. É a linha do veredito.
      estrato_x_dias  por (estrato, faixa de dias entre os dois jogos). O controle do calendário.
      time            por (time, estrato), só para os times que TÊM par liga↔copa — são os times
                      sobre os quais a pergunta do ticket existe. Quantos ficaram de fora por não
                      ter nenhum sai na linha `total`, em `times_sem_par_liga_copa`.
      times_do_universo  por categoria de time: quem é cada um dos que ficaram de fora. Existe
                      porque o `times_sem_par_liga_copa` sozinho convida à leitura "não jogam as
                      duas coisas", que é verdade para a maioria e falsa para uma parte — há
                      clube de liga que simplesmente não teve jogo de copa dentro do teto, e há
                      quem jogue os dois sem que dois deles caiam consecutivos. `lados` aqui é
                      jogo no pool (não lado), e `times_sem_par_nenhum` conta quem tem um jogo só.

    Somar linhas de níveis diferentes conta o mesmo par mais de uma vez — filtre `nivel` sempre.

    COMO RODAR (do dbt_futebol/):

      # uma vez, se os nós abaixo ainda não estiverem no dataset de medição — a ancestria das
      # células não passa por eles, e nenhum dos seis nós de premissas os referencia
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt run --target taskF \
        --select dim_leagues stg_futebol_leagues dim_teams stg_futebol_teams \
                 fact_fixture_lineups_players stg_futebol_fixture_lineups_players

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_rodizio_de_elenco
      bq query --use_legacy_sql=false --max_rows=100000 --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_rodizio_de_elenco.sql

    ⚠️ DUAS ARMADILHAS DO `bq query`, as duas silenciosas. O SQL como ARGUMENTO trava nesta
    máquina (sempre por redirecionamento). E o `--max_rows` PRECISA estar lá: o default é 100
    linhas e ele TRUNCA sem avisar — a saída sai com cara de completa, e a linha que falta é
    exatamente a do fim da ordenação. Custou uma contagem errada de times durante a própria #57.

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

,

apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE (kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00'))
),

universo AS (
    SELECT DISTINCT fixture_id FROM apostas_congeladas
),

fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season, kickoff_utc,
        status_short, home_team_id, away_team_id, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

tipo_competicao AS (
    SELECT DISTINCT league_id AS competition_id, league_type
    FROM `smartbetting-dados`.`futebol`.`dim_leagues`
),

times_na_base AS (
    SELECT DISTINCT lados.team_id
    FROM (
        SELECT home_team_id AS team_id, competition_id FROM fixtures
        UNION ALL
        SELECT away_team_id,            competition_id FROM fixtures
    ) AS lados
    JOIN tipo_competicao AS t
      ON  t.competition_id = lados.competition_id
     AND  t.league_type    = 'League'
),

times_do_universo AS (
    SELECT DISTINCT lado AS team_id, f.season
    FROM fixtures AS f
    JOIN universo USING (fixture_id)
    CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
),

pool AS (
    SELECT
        t.team_id,
        f.fixture_id,
        f.competition,
        f.kickoff_utc,
        tc.league_type
    FROM times_do_universo AS t
    JOIN fixtures AS f
      ON  f.season = t.season
      AND t.team_id IN (f.home_team_id, f.away_team_id)
    JOIN tipo_competicao AS tc
      ON tc.competition_id = f.competition_id
    WHERE f.status_short = 'FT'
      AND f.goals_home IS NOT NULL
      AND f.goals_away IS NOT NULL
      AND f.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')
),

xi AS (
    SELECT
        fixture_id,
        team_id,
        ARRAY_AGG(player_id) AS jogadores,
        COUNT(*)             AS n_titulares
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_lineups_players`
    WHERE is_starter
      AND lineup_phase = 'real'
    GROUP BY fixture_id, team_id
),

xi_sem_filtro AS (
    SELECT
        fixture_id,
        team_id,
        CAST(NULL AS ARRAY<INT64>) AS jogadores,
        COUNT(*)                   AS n_titulares
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_lineups_players`
    WHERE is_starter
    GROUP BY fixture_id, team_id
),

lados_da_temporada AS (
    SELECT f.fixture_id, f.competition, lado AS team_id
    FROM fixtures AS f
    CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
    WHERE f.status_short = 'FT'
      AND f.goals_home IS NOT NULL
      AND f.goals_away IS NOT NULL
      AND f.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')
      AND f.season IN (SELECT DISTINCT season FROM times_do_universo)
),

cobertura AS (
    SELECT
        p.competition,
        'pool' AS escopo,
        
        COUNT(*)                                                  AS lados,
        COUNTIF(x.n_titulares = 11)                               AS lados_com_xi,
        COUNTIF(x.fixture_id IS NULL)                             AS lados_sem_lineup,
        COUNTIF(x.fixture_id IS NOT NULL AND x.n_titulares != 11) AS lados_xi_incompleto
    FROM pool AS p
    LEFT JOIN xi AS x
           ON  x.fixture_id = p.fixture_id
          AND  x.team_id    = p.team_id
    GROUP BY p.competition

    UNION ALL

    SELECT
        p.competition,
        'temporada',
        
        COUNT(*)                                                  AS lados,
        COUNTIF(x.n_titulares = 11)                               AS lados_com_xi,
        COUNTIF(x.fixture_id IS NULL)                             AS lados_sem_lineup,
        COUNTIF(x.fixture_id IS NOT NULL AND x.n_titulares != 11) AS lados_xi_incompleto
    FROM lados_da_temporada AS p
    LEFT JOIN xi AS x
           ON  x.fixture_id = p.fixture_id
          AND  x.team_id    = p.team_id
    GROUP BY p.competition

    UNION ALL

    SELECT
        p.competition,
        'temporada_sem_filtro_de_fase',
        
        COUNT(*)                                                  AS lados,
        COUNTIF(x.n_titulares = 11)                               AS lados_com_xi,
        COUNTIF(x.fixture_id IS NULL)                             AS lados_sem_lineup,
        COUNTIF(x.fixture_id IS NOT NULL AND x.n_titulares != 11) AS lados_xi_incompleto
    FROM lados_da_temporada AS p
    LEFT JOIN xi_sem_filtro AS x
           ON  x.fixture_id = p.fixture_id
          AND  x.team_id    = p.team_id
    GROUP BY p.competition
),

sequencia AS (
    SELECT
        team_id,
        fixture_id,
        kickoff_utc,
        league_type,
        LAG(fixture_id)  OVER (PARTITION BY team_id ORDER BY kickoff_utc) AS fixture_anterior,
        LAG(kickoff_utc) OVER (PARTITION BY team_id ORDER BY kickoff_utc) AS kickoff_anterior,
        LAG(league_type) OVER (PARTITION BY team_id ORDER BY kickoff_utc) AS tipo_anterior
    FROM pool
),

pares AS (
    SELECT
        s.team_id,
        CASE
            WHEN s.league_type = 'League' AND s.tipo_anterior = 'League' THEN 'liga_liga'
            WHEN s.league_type = 'Cup'    AND s.tipo_anterior = 'Cup'    THEN 'copa_copa'
            ELSE                                                             'liga_copa'
        END                                                       AS estrato,
        TIMESTAMP_DIFF(s.kickoff_utc, s.kickoff_anterior, DAY)    AS dias_entre,COALESCE(xa.n_titulares, 0) = 11
            AND COALESCE(xb.n_titulares, 0) = 11                  AS utilizavel,
        (SELECT COUNT(*) FROM UNNEST(xa.jogadores) AS j
          WHERE j IN UNNEST(xb.jogadores))                        AS sobreposicao
    FROM sequencia AS s
    LEFT JOIN xi AS xa
           ON  xa.fixture_id = s.fixture_id
          AND  xa.team_id    = s.team_id
    LEFT JOIN xi AS xb
           ON  xb.fixture_id = s.fixture_anterior
          AND  xb.team_id    = s.team_id
    WHERE s.fixture_anterior IS NOT NULL
),



por_estrato AS (
    SELECT estrato, 
        COUNT(*)                                                        AS pares_no_estrato,
        COUNTIF(utilizavel)                                             AS pares,
        COUNTIF(NOT utilizavel)                                         AS pares_descartados,
        COUNT(DISTINCT IF(utilizavel, team_id, NULL))                   AS times,ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, sobreposicao, 0)),
                          COUNTIF(utilizavel)), 2)                      AS sobreposicao_media,
        ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, sobreposicao, 0)),
                          COUNTIF(utilizavel)) / 11 * 100, 1)           AS pct_sobreposicao,
        
    ROUND(
        ARRAY_AGG(IF(utilizavel, sobreposicao, NULL) IGNORE NULLS ORDER BY IF(utilizavel, sobreposicao, NULL))
            [SAFE_OFFSET(DIV(COUNTIF((IF(utilizavel, sobreposicao, NULL)) IS NOT NULL) - 1, 2))],
        0) AS sobreposicao_mediana,
        MIN(IF(utilizavel, sobreposicao, NULL))                         AS sobreposicao_min,
        ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, dias_entre, 0)),
                          COUNTIF(utilizavel)), 1)                      AS dias_entre_medio
    FROM pares
    GROUP BY estrato
),

por_estrato_dias AS (
    SELECT
        estrato,
        CASE
            WHEN dias_entre <= 3 THEN 'ate_3'
            WHEN dias_entre BETWEEN 4 AND 5 THEN '4_a_5'
            WHEN dias_entre BETWEEN 6 AND 7 THEN '6_a_7'
            WHEN dias_entre >= 8 THEN '8_ou_mais'
        END AS faixa_de_dias,
        
        COUNT(*)                                                        AS pares_no_estrato,
        COUNTIF(utilizavel)                                             AS pares,
        COUNTIF(NOT utilizavel)                                         AS pares_descartados,
        COUNT(DISTINCT IF(utilizavel, team_id, NULL))                   AS times,ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, sobreposicao, 0)),
                          COUNTIF(utilizavel)), 2)                      AS sobreposicao_media,
        ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, sobreposicao, 0)),
                          COUNTIF(utilizavel)) / 11 * 100, 1)           AS pct_sobreposicao,
        
    ROUND(
        ARRAY_AGG(IF(utilizavel, sobreposicao, NULL) IGNORE NULLS ORDER BY IF(utilizavel, sobreposicao, NULL))
            [SAFE_OFFSET(DIV(COUNTIF((IF(utilizavel, sobreposicao, NULL)) IS NOT NULL) - 1, 2))],
        0) AS sobreposicao_mediana,
        MIN(IF(utilizavel, sobreposicao, NULL))                         AS sobreposicao_min,
        ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, dias_entre, 0)),
                          COUNTIF(utilizavel)), 1)                      AS dias_entre_medio
    FROM pares
    GROUP BY estrato, faixa_de_dias
),

times_com_par_misto AS (
    SELECT DISTINCT team_id
    FROM pares
    WHERE estrato = 'liga_copa' AND utilizavel
),

por_time AS (
    SELECT p.team_id, p.estrato, 
        COUNT(*)                                                        AS pares_no_estrato,
        COUNTIF(utilizavel)                                             AS pares,
        COUNTIF(NOT utilizavel)                                         AS pares_descartados,
        COUNT(DISTINCT IF(utilizavel, team_id, NULL))                   AS times,ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, sobreposicao, 0)),
                          COUNTIF(utilizavel)), 2)                      AS sobreposicao_media,
        ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, sobreposicao, 0)),
                          COUNTIF(utilizavel)) / 11 * 100, 1)           AS pct_sobreposicao,
        
    ROUND(
        ARRAY_AGG(IF(utilizavel, sobreposicao, NULL) IGNORE NULLS ORDER BY IF(utilizavel, sobreposicao, NULL))
            [SAFE_OFFSET(DIV(COUNTIF((IF(utilizavel, sobreposicao, NULL)) IS NOT NULL) - 1, 2))],
        0) AS sobreposicao_mediana,
        MIN(IF(utilizavel, sobreposicao, NULL))                         AS sobreposicao_min,
        ROUND(SAFE_DIVIDE(SUM(IF(utilizavel, dias_entre, 0)),
                          COUNTIF(utilizavel)), 1)                      AS dias_entre_medio
    FROM pares AS p
    JOIN times_com_par_misto USING (team_id)
    GROUP BY p.team_id, p.estrato
),

perfil_do_time AS (
    SELECT
        team_id,
        COUNT(*)                          AS jogos_no_pool,
        COUNTIF(league_type = 'League')    AS jogos_de_liga,
        COUNTIF(league_type = 'Cup')       AS jogos_de_copa
    FROM pool
    GROUP BY team_id
),

categoria_do_time AS (
    SELECT
        t.team_id,
        t.jogos_no_pool,
        CASE
            WHEN dt.national          THEN 'selecao'
            WHEN b.team_id IS NULL    THEN 'clube_sem_liga_na_coleta'
            WHEN t.jogos_de_copa = 0  THEN 'clube_de_liga_sem_copa_no_pool'
            WHEN t.jogos_de_liga = 0  THEN 'clube_so_de_copa_no_pool'
            ELSE                           'joga_os_dois'
        END AS categoria
    FROM perfil_do_time AS t
    LEFT JOIN `smartbetting-dados`.`futebol`.`dim_teams` AS dt USING (team_id)
    LEFT JOIN times_na_base          AS b  USING (team_id)
),

por_categoria AS (
    SELECT
        categoria,
        COUNT(*)                                                          AS times,
        SUM(jogos_no_pool)                                                AS jogos_no_pool,
        COUNTIF(team_id IN (SELECT team_id FROM times_com_par_misto))     AS times_com_par_liga_copa,
        COUNTIF(jogos_no_pool = 1)                                        AS times_sem_par_nenhum
    FROM categoria_do_time
    GROUP BY categoria
),

empilhado AS (
    SELECT
        'cobertura'           AS nivel,
        0                     AS nivel_ord,
        competition           AS chave,
        escopo                AS chave2,
        lados,
        lados_com_xi,
        lados_sem_lineup,
        lados_xi_incompleto,
        ROUND(SAFE_DIVIDE(lados_com_xi, lados) * 100, 1) AS pct_com_xi,
        CAST(NULL AS INT64)   AS pares_no_estrato,
        CAST(NULL AS INT64)   AS pares,
        CAST(NULL AS INT64)   AS pares_descartados,
        CAST(NULL AS INT64)   AS times,
        CAST(NULL AS FLOAT64) AS sobreposicao_media,
        CAST(NULL AS FLOAT64) AS pct_sobreposicao,
        CAST(NULL AS INT64)   AS sobreposicao_mediana,
        CAST(NULL AS INT64)   AS sobreposicao_min,
        CAST(NULL AS FLOAT64) AS dias_entre_medio,
        CAST(NULL AS INT64)   AS times_sem_par_liga_copa,
        CAST(NULL AS INT64)   AS times_com_par_liga_copa,
        CAST(NULL AS INT64)   AS times_sem_par_nenhum
    FROM cobertura

    UNION ALL

    SELECT
        'total', 1, estrato, CAST(NULL AS STRING),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        pares_no_estrato, pares, pares_descartados, times,
        sobreposicao_media, pct_sobreposicao, sobreposicao_mediana, sobreposicao_min,
        dias_entre_medio,
        (SELECT COUNT(DISTINCT team_id) FROM pares
          WHERE team_id NOT IN (SELECT team_id FROM times_com_par_misto)),
        CAST(NULL AS INT64), CAST(NULL AS INT64)
    FROM por_estrato

    UNION ALL

    SELECT
        'estrato_x_dias', 2, estrato, faixa_de_dias,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        pares_no_estrato, pares, pares_descartados, times,
        sobreposicao_media, pct_sobreposicao, sobreposicao_mediana, sobreposicao_min,
        dias_entre_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64)
    FROM por_estrato_dias

    UNION ALL

    SELECT
        'time', 3, COALESCE(t.team_name, FORMAT('team_id=%d', p.team_id)), p.estrato,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        p.pares_no_estrato, p.pares, p.pares_descartados, p.times,
        p.sobreposicao_media, p.pct_sobreposicao, p.sobreposicao_mediana, p.sobreposicao_min,
        p.dias_entre_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64)
    FROM por_time AS p
    LEFT JOIN `smartbetting-dados`.`futebol`.`dim_teams` AS t USING (team_id)

    UNION ALL

    SELECT
        'times_do_universo', 4, categoria, CAST(NULL AS STRING),
        jogos_no_pool, CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), times,
        CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        CAST(NULL AS INT64), times_com_par_liga_copa, times_sem_par_nenhum
    FROM por_categoria
)

SELECT *
FROM empilhado
ORDER BY nivel_ord, chave, chave2