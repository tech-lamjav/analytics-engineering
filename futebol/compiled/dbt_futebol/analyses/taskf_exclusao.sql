/*
    [F-9] EXCLUIR UM CONJUNTO DE JOGOS DA BASE DE MEDIÇÃO MUDA A ORDENAÇÃO DAS PREMISSAS? —
    medido COM e SEM, sobre a mesma materialização das quatro células.

    A spec #49 pede duas recomendações do mesmo tipo (user stories 7 e 24): a Copa do Mundo deve
    sair da base de medição, já que ali o deserto de histórico é real e ela pesa 47% da amostra? E
    a mesma pergunta para a fase classificatória da Champions. O critério de aceite da #58 é
    explícito sobre COMO responder: "a recomendação sai do efeito na ordenação das premissas, não
    do bom senso — o argumento de princípio fica declarado como reserva".

    Esta análise é esse efeito. Ela não decide nada sozinha: emite as três métricas declaradas
    abaixo, o veredito mecânico delas, e o contraste de referência que dá escala ao veredito.

    ────────────────────────────────────────────────────────────────────────────────
    A RÉGUA, DECLARADA ANTES DE MEDIR

    Mesmo padrão da tolerância da #51: o número existe antes do resultado, para não ser escolhido
    depois de ver qual lado ele favorece.

    ⚠️ O paralelo vale para o MÉTODO, não para o número: aquela tolerância era 0,5 pp e a #92 a
    remediu para 0,25 pp — ou seja, "declarado antes de medir" foi o começo dela, e não onde ela
    ficou. Declarar antes protege da escolha conveniente; não dispensa remedir quando o fenômeno
    que justificava o número muda.

    O que é ORDENAR. As 39 premissas do benchmark preferido (`usado_para_peso`), ordenadas por
    `diferenca_p<piso>` — o sinal medido, decrescente. É a ordenação que a [B] leria para decidir
    em quem mexer.

    TRÊS MÉTRICAS, por (célula, piso):

      rho             correlação de Spearman entre as duas ordenações (Pearson sobre os postos).
                      1,0 = a exclusão não mexeu em nada; 0 = a ordenação virou outra.
      trocas_no_topo  quantas premissas entram ou saem do TOP 5 por `peso_p<piso>`. O peso é o que
                      a [B] usaria como peso, e o topo é onde uma decisão de fato acontece.
      trocas_de_sinal quantas das 39 trocam o SINAL da diferença. Trocar de sinal é mudar a
                      resposta ("essa premissa tem ganho" ↔ "não tem"), não a posição.

    VEREDITO. A exclusão é MATERIAL naquele (célula, piso) quando QUALQUER uma valer:

        rho < 0,90     OU     trocas_no_topo >= 2     OU     trocas_de_sinal >= 4

    Fora disso, IMATERIAL. Os três cortes são grosseiros de propósito: eles separam "a ordenação
    é outra" de "a ordenação é a mesma com ruído", e não pretendem medir significância.

    ⚠️ E POR ISSO O CONTRASTE DE REFERÊNCIA VEM JUNTO. Um `rho` de 0,93 não diz nada sozinho —
    0,93 é muito ou pouco? A referência responde: as MESMAS três métricas para o par de células
    `base` → `escopo` DENTRO do universo COM. Esse é o efeito que a [F] existe para medir e que a
    #53 chamou de grande (30,6% dos pares ganham histórico, o piso 5 vai de 69 para 92 jogos). Se
    a exclusão mexer na ordenação MENOS do que o eixo que a task mede, ela é ruído perto do que se
    está medindo; se mexer mais, a base de medição está sendo decidida por ela.

    ⚠️ O QUE FAZER SE O VEREDITO SAIR AMBÍGUO — declarado agora, para não ser escolhido depois. Se
    as métricas caírem perto dos cortes (rho entre 0,88 e 0,92, ou trocas_no_topo = 1 com
    trocas_de_sinal = 3), a resposta NÃO é arredondar para o lado conveniente: é acrescentar um
    universo de placebo — remover N jogos sorteados por hash, do mesmo tamanho do conjunto
    excluído — e comparar a exclusão real contra a distribuição do placebo. Isso é uma medição a
    mais (um universo novo em macros/taskf_universos.sql e a re-medição das quatro células), e não
    foi feita de partida porque a exclusão da Copa do Mundo se sobrepõe ao piso de amostra (bloco
    `excluido` abaixo): no piso 5 quase todos os jogos que ela remove JÁ estavam fora.

    ────────────────────────────────────────────────────────────────────────────────
    OS SETE BLOCOS

      universo    quantos jogos e linhas cada universo tem, por célula, e quantos a exclusão
                  remove. É a conferência de que o par pedido é encaixado (SEM ⊂ COM) e não-vazio
                  — duas coisas que, se falharem, fazem o resto da saída parecer resultado.
      excluido    QUEM são os jogos removidos: quanto histórico eles têm e quantos deles já
                  estavam abaixo do piso de amostra. É aqui que se vê a sobreposição entre excluir
                  e usar piso — e ela é o mecanismo por trás do veredito, não um detalhe.
      composicao  o universo COM por competição. No par da Copa do Mundo ele reproduz a
                  composição dos 169 que a #51 publicou; no par da Champions ele é a composição do
                  universo ESTENDIDO, que é o que a user story 5 da #58 pede reportado à parte.
      fases       os jogos removidos por (competição, fase), contra o total daquela competição no
                  universo COM. É o que transforma "excluir a fase classificatória ≡ excluir a
                  Champions **nesta janela**" de afirmação em número.
      fora_do_universo  as partidas ENCERRADAS das competições que a exclusão toca e que mesmo
                  assim não entram no universo, por fase e por status. É o que separa "não
                  medimos" de "não aconteceu" — e responde de uma vez as duas perguntas que
                  costumam vir depois de uma contagem baixa: a partida sem preço coletado e a que
                  terminou fora do tempo normal (`status_short <> 'FT'`, o filtro do
                  task01_base(); ver a issue #71).
      ordenacao   as três métricas e o veredito, por (contraste, piso) — as quatro células mais o
                  contraste de referência.
      topo        as premissas que ENTRARAM ou SAÍRAM do top , com posição e peso dos
                  dois lados. Sem ele, `trocas_no_topo = 2` é um número sem conteúdo: não dá para
                  saber se foi uma permuta adjacente na fronteira ou duas premissas atravessando a
                  tabela inteira, e as duas coisas pedem leituras opostas.

    ────────────────────────────────────────────────────────────────────────────────
    AS COLUNAS `a`, `b`, `c` MUDAM DE SENTIDO POR BLOCO — é o preço de sete blocos num UNION, e a
    legenda é esta (o `detalhe` traz o resto sempre):

      universo          a = jogos no COM      b = jogos no SEM     c = jogos removidos
      excluido          a = jogos excluídos   b = min_jogos médio  c = excluídos acima do piso 5
      composicao        a = jogos             b = % do universo    c = jogos removidos
      fases             a = jogos na fase     b = jogos removidos  c = —
      fora_do_universo  a = partidas de fora  b = com preço        c = —
      ordenacao         a = rho               b = trocas no topo   c = trocas de sinal
      topo              a = posição no COM    b = posição no SEM   c = peso no COM

    ────────────────────────────────────────────────────────────────────────────────
    COMO RODAR (do dbt_futebol/), depois das quatro células medidas:

      # Copa do Mundo (default)
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_exclusao
      bq query --use_legacy_sql=false --project_id=smartbetting-dados --max_rows=500 \
        < target/compiled/dbt_futebol/analyses/taskf_exclusao.sql

      # Champions, fase classificatória
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_exclusao \
        --vars '{taskf_universo_com: estendido,
                 taskf_universo_sem: estendido_sem_champions_classif}'

    ⚠️ `--max_rows` não é enfeite: o `bq query` trunca a saída em 100 linhas SEM AVISAR, e esta
    análise emite mais do que isso. Foi assim que a #57 quase publicou uma conta pela metade.

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


jogos_marcados AS (
    SELECT DISTINCT
        a.fixture_id,
        a.competition,
        a.kickoff_utc,
        COALESCE(f.round, '') AS round
    FROM apostas AS a
    LEFT JOIN `smartbetting-dados`.`futebol`.`fact_fixtures` AS f
           ON f.fixture_id = a.fixture_id
),


classificado AS (
    SELECT
        j.*,
        (kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AS no_com,
        ((kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND competition <> 'copa_mundo') AS no_sem
    FROM jogos_marcados AS j
),

excluidos AS (
    SELECT * FROM classificado WHERE no_com AND NOT no_sem
),


pit_por_jogo AS (
    SELECT
        celula,
        fixture_id,
        MIN(played_total_disponivel) AS min_disp
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula`
    GROUP BY celula, fixture_id
),

-- ── bloco `universo` ────────────────────────────────────────────────────────────────────────

universo_medido AS (
    SELECT
        celula,
        universo,
        ANY_VALUE(jogos_no_universo)  AS jogos,
        ANY_VALUE(linhas_no_universo) AS linhas,
        ANY_VALUE(janela_ini)         AS janela_ini,
        ANY_VALUE(janela_fim)         AS janela_fim,
        COUNT(*)                      AS linhas_de_premissa
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE universo IN ('completo', 'sem_copa_mundo')
    GROUP BY celula, universo
),

bloco_universo AS (
    SELECT
        c.celula,
        c.jogos                       AS jogos_com,
        s.jogos                       AS jogos_sem,
        c.jogos - s.jogos             AS jogos_removidos,
        c.linhas                      AS linhas_com,
        s.linhas                      AS linhas_sem,
        c.linhas_de_premissa          AS premissas_com,
        s.linhas_de_premissa          AS premissas_sem,
        c.janela_ini, c.janela_fim,
        s.janela_ini AS janela_ini_sem, s.janela_fim AS janela_fim_sem,
        (SELECT COUNT(*) FROM excluidos)                     AS jogos_excluidos_pelo_predicado,
        (SELECT COUNTIF(NOT no_com AND no_sem) FROM classificado) AS jogos_so_no_sem
    FROM universo_medido AS c
    JOIN universo_medido AS s
      ON s.celula = c.celula AND s.universo = 'sem_copa_mundo'
    WHERE c.universo = 'completo'
),

-- ── bloco `excluido` ────────────────────────────────────────────────────────────────────────

bloco_excluido AS (
    SELECT
        p.celula,
        COUNT(*)                                   AS jogos_excluidos,
        ROUND(AVG(p.min_disp), 2)                  AS min_jogos_medio,
        MAX(p.min_disp)                            AS min_jogos_max,
        COUNTIF(p.min_disp >= 0)          AS excluidos_acima_p0,
        COUNTIF(p.min_disp >= 3)          AS excluidos_acima_p3,
        COUNTIF(p.min_disp >= 5)          AS excluidos_acima_p5,
        COUNTIF(p.min_disp >= 10)          AS excluidos_acima_p10
    FROM excluidos AS e
    JOIN pit_por_jogo AS p USING (fixture_id)
    GROUP BY p.celula
),


bloco_denominador AS (
    SELECT
        p.celula,
        COUNT(*)                                   AS jogos_no_com,
        COUNTIF(p.min_disp >= 0)          AS com_acima_p0,
        COUNTIF(p.min_disp >= 3)          AS com_acima_p3,
        COUNTIF(p.min_disp >= 5)          AS com_acima_p5,
        COUNTIF(p.min_disp >= 10)          AS com_acima_p10
    FROM classificado AS c
    JOIN pit_por_jogo AS p USING (fixture_id)
    WHERE c.no_com
    GROUP BY p.celula
),

-- ── bloco `composicao` ──────────────────────────────────────────────────────────────────────

bloco_composicao AS (
    SELECT
        c.competition,
        COUNT(*)                 AS jogos,
        COUNTIF(NOT c.no_sem)    AS jogos_removidos,
        MIN(DATE(c.kickoff_utc)) AS primeiro,
        MAX(DATE(c.kickoff_utc)) AS ultimo
    FROM classificado AS c
    WHERE c.no_com
    GROUP BY c.competition
),

-- ── bloco `fases` ───────────────────────────────────────────────────────────────────────────

bloco_fases AS (
    SELECT
        c.competition,
        c.round,
        COUNT(*)                    AS jogos_no_com,
        COUNTIF(NOT c.no_sem)       AS jogos_removidos,
        MIN(DATE(c.kickoff_utc))    AS primeiro,
        MAX(DATE(c.kickoff_utc))    AS ultimo
    FROM classificado AS c
    WHERE c.no_com
      AND c.competition IN (SELECT DISTINCT competition FROM excluidos)
    GROUP BY c.competition, c.round
),

-- ── bloco `fora_do_universo` ────────────────────────────────────────────────────────────────

fora_do_universo AS (
    SELECT
        f.competition,
        f.round,
        f.status_short,
        COUNT(*) AS partidas,
        COUNTIF(o.fixture_id IS NOT NULL) AS com_preco,
        MIN(DATE(f.kickoff_utc)) AS primeiro,
        MAX(DATE(f.kickoff_utc)) AS ultimo
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures` AS f
    LEFT JOIN (SELECT DISTINCT fixture_id FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`) AS o
           ON o.fixture_id = f.fixture_id
    WHERE f.kickoff_utc >= TIMESTAMP('2026-06-16')
      AND f.status_short IN ('FT', 'AET', 'PEN')
      AND f.competition IN (SELECT DISTINCT competition FROM excluidos)
      AND f.fixture_id NOT IN (SELECT fixture_id FROM jogos_marcados)
    GROUP BY f.competition, f.round, f.status_short
),

-- ── bloco `ordenacao` ───────────────────────────────────────────────────────────────────────

lados AS (
    SELECT 'exclusao__base' AS contraste, 'A' AS lado, mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'base' AND universo = 'completo'
    UNION ALL
    SELECT 'exclusao__base', 'B', mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'base' AND universo = 'sem_copa_mundo'
    UNION ALL
    SELECT 'exclusao__escopo' AS contraste, 'A' AS lado, mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'escopo' AND universo = 'completo'
    UNION ALL
    SELECT 'exclusao__escopo', 'B', mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'escopo' AND universo = 'sem_copa_mundo'
    UNION ALL
    SELECT 'exclusao__recorte' AS contraste, 'A' AS lado, mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'recorte' AND universo = 'completo'
    UNION ALL
    SELECT 'exclusao__recorte', 'B', mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'recorte' AND universo = 'sem_copa_mundo'
    UNION ALL
    SELECT 'exclusao__ambos' AS contraste, 'A' AS lado, mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'ambos' AND universo = 'completo'
    UNION ALL
    SELECT 'exclusao__ambos', 'B', mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'ambos' AND universo = 'sem_copa_mundo'
    UNION ALL
    SELECT 'eixo__base_escopo', 'A', mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'base' AND universo = 'completo'
    UNION ALL
    SELECT 'eixo__base_escopo', 'B', mercado, premissa, benchmark,
           diferenca_p0, peso_p0, n_p0, diferenca_p3, peso_p3, n_p3, diferenca_p5, peso_p5, n_p5, diferenca_p10, peso_p10, n_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` WHERE usado_para_peso AND celula = 'escopo' AND universo = 'completo'
),


longo AS (
    SELECT
        l.contraste, l.lado, l.mercado, l.premissa, l.benchmark,
        p.piso, p.diferenca, p.peso, p.n
    FROM lados AS l,
    UNNEST([
        STRUCT(0 AS piso, l.diferenca_p0 AS diferenca,
               l.peso_p0 AS peso, l.n_p0 AS n),
        STRUCT(3 AS piso, l.diferenca_p3 AS diferenca,
               l.peso_p3 AS peso, l.n_p3 AS n),
        STRUCT(5 AS piso, l.diferenca_p5 AS diferenca,
               l.peso_p5 AS peso, l.n_p5 AS n),
        STRUCT(10 AS piso, l.diferenca_p10 AS diferenca,
               l.peso_p10 AS peso, l.n_p10 AS n)
    ]) AS p
),

pareado AS (
    SELECT
        contraste, piso, mercado, premissa, benchmark,
        MAX(IF(lado = 'A', diferenca, NULL)) AS dif_a,
        MAX(IF(lado = 'B', diferenca, NULL)) AS dif_b,
        MAX(IF(lado = 'A', peso, NULL))      AS peso_a,
        MAX(IF(lado = 'B', peso, NULL))      AS peso_b,
        MAX(IF(lado = 'A', n, NULL))         AS n_a,
        MAX(IF(lado = 'B', n, NULL))         AS n_b,
        COUNTIF(lado = 'A') AS tem_a,
        COUNTIF(lado = 'B') AS tem_b
    FROM longo
    GROUP BY contraste, piso, mercado, premissa, benchmark
),


ranqueado AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY contraste, piso ORDER BY dif_a DESC) AS rank_a,
        RANK() OVER (PARTITION BY contraste, piso ORDER BY dif_b DESC) AS rank_b
    FROM pareado
    WHERE tem_a = 1 AND tem_b = 1
      AND dif_a IS NOT NULL AND dif_b IS NOT NULL
),


topo AS (
    SELECT
        contraste, piso, mercado, premissa, benchmark,
        ROW_NUMBER() OVER (PARTITION BY contraste, piso
                           ORDER BY peso_a DESC, mercado, premissa) AS pos_a,
        ROW_NUMBER() OVER (PARTITION BY contraste, piso
                           ORDER BY peso_b DESC, mercado, premissa) AS pos_b
    FROM pareado
    WHERE tem_a = 1 AND tem_b = 1
),

trocas_topo AS (
    SELECT
        contraste, piso,
        COUNTIF((pos_a <= 5) != (pos_b <= 5)) AS entradas_e_saidas,
        STRING_AGG(IF(pos_a <= 5 AND pos_b > 5, premissa, NULL),
                   ', ' ORDER BY pos_a) AS saiu_do_topo,
        STRING_AGG(IF(pos_b <= 5 AND pos_a > 5, premissa, NULL),
                   ', ' ORDER BY pos_b) AS entrou_no_topo
    FROM topo
    GROUP BY contraste, piso
),

metricas AS (
    SELECT
        r.contraste,
        r.piso,
        COUNT(*)                                                   AS n_premissas,
        ROUND(CORR(r.rank_a, r.rank_b), 4)                         AS rho,
        COUNTIF(SIGN(r.dif_a) != SIGN(r.dif_b))                    AS trocas_de_sinal,
        ROUND(AVG(ABS(r.dif_a - r.dif_b)), 2)                      AS delta_dif_medio,
        MAX(ABS(r.rank_a - r.rank_b))                              AS max_delta_posto,
        ROUND(AVG(r.n_a), 1)                                       AS n_medio_a,
        ROUND(AVG(r.n_b), 1)                                       AS n_medio_b
    FROM ranqueado AS r
    GROUP BY r.contraste, r.piso
),

descartes AS (
    SELECT
        contraste, piso,
        COUNTIF(tem_a = 0 OR tem_b = 0)                                     AS sem_contraparte,
        COUNTIF(tem_a = 1 AND tem_b = 1
                AND (dif_a IS NULL OR dif_b IS NULL))                       AS sem_medida,
        STRING_AGG(IF(tem_a = 0 OR tem_b = 0, premissa, NULL), ', ')        AS quais_sem_contraparte
    FROM pareado
    GROUP BY contraste, piso
),

bloco_ordenacao AS (
    SELECT
        m.contraste,
        m.piso,
        m.rho,
        t.entradas_e_saidas AS trocas_no_topo,
        m.trocas_de_sinal,
        m.n_premissas,
        d.sem_contraparte,
        d.sem_medida,
        d.quais_sem_contraparte,
        t.saiu_do_topo,
        t.entrou_no_topo,
        m.delta_dif_medio,
        m.max_delta_posto,
        m.n_medio_a,
        m.n_medio_b,
        IF(m.rho < 0.9
           OR t.entradas_e_saidas >= 2
           OR m.trocas_de_sinal   >= 4,
           'MATERIAL', 'IMATERIAL')                                          AS veredito
    FROM metricas AS m
    JOIN trocas_topo AS t USING (contraste, piso)
    JOIN descartes   AS d USING (contraste, piso)
),


bloco_topo AS (
    SELECT
        t.contraste,
        t.piso,
        t.premissa,
        t.mercado,
        t.pos_a,
        t.pos_b,
        p.peso_a,
        p.peso_b,
        IF(t.pos_a <= 5, 'saiu', 'entrou') AS direcao
    FROM topo AS t
    JOIN pareado AS p USING (contraste, piso, mercado, premissa, benchmark)
    WHERE (t.pos_a <= 5) != (t.pos_b <= 5)
)

-- ── saída ───────────────────────────────────────────────────────────────────────────────────
SELECT 1 AS ordem, 'universo' AS bloco,
    celula AS chave,
    IF(jogos_removidos > 0 AND jogos_so_no_sem = 0, 'OK', 'PAR_NAO_ENCAIXADO') AS veredito,
    CAST(jogos_com AS FLOAT64)       AS a,
    CAST(jogos_sem AS FLOAT64)       AS b,
    CAST(jogos_removidos AS FLOAT64) AS c,
    TO_JSON_STRING(STRUCT(
        'completo' AS universo_com, 'sem_copa_mundo' AS universo_sem,
        linhas_com, linhas_sem, premissas_com, premissas_sem,
        janela_ini, janela_fim, janela_ini_sem, janela_fim_sem,
        jogos_excluidos_pelo_predicado, jogos_so_no_sem
    )) AS detalhe
FROM bloco_universo

UNION ALL
SELECT 2, 'excluido',
    e.celula,
    -- Quanto do conjunto excluído o piso 5 já removia por conta própria. É a leitura que decide
    -- se a exclusão tem como mudar alguma coisa naquele piso.
    FORMAT('%d de %d acima do piso 5', e.excluidos_acima_p5, e.jogos_excluidos),
    CAST(e.jogos_excluidos AS FLOAT64),
    e.min_jogos_medio,
    CAST(e.excluidos_acima_p5 AS FLOAT64),
    TO_JSON_STRING(STRUCT(
        e.min_jogos_max,
        e.excluidos_acima_p0, d.com_acima_p0,
        e.excluidos_acima_p3, d.com_acima_p3,
        e.excluidos_acima_p5, d.com_acima_p5,
        e.excluidos_acima_p10, d.com_acima_p10,
        d.jogos_no_com
    ))
FROM bloco_excluido AS e
JOIN bloco_denominador AS d USING (celula)

UNION ALL
SELECT 3, 'composicao',
    competition,
    IF(jogos_removidos = 0, 'INTACTA',
       IF(jogos_removidos = jogos, 'REMOVIDA_INTEIRA', 'PARCIAL')),
    CAST(jogos AS FLOAT64),
    ROUND(100 * jogos / SUM(jogos) OVER (), 1),
    CAST(jogos_removidos AS FLOAT64),
    TO_JSON_STRING(STRUCT(competition, jogos, jogos_removidos, primeiro, ultimo,
                          SUM(jogos) OVER () AS jogos_no_universo))
FROM bloco_composicao

UNION ALL
SELECT 4, 'fases',
    FORMAT('%s · %s', competition, round),
    IF(jogos_removidos = jogos_no_com, 'FASE_INTEIRA',
       IF(jogos_removidos = 0, 'INTACTA', 'PARCIAL')),
    CAST(jogos_no_com AS FLOAT64),
    CAST(jogos_removidos AS FLOAT64),
    NULL,
    TO_JSON_STRING(STRUCT(competition, round, jogos_no_com, jogos_removidos, primeiro, ultimo))
FROM bloco_fases

UNION ALL
SELECT 5, 'fora_do_universo',
    FORMAT('%s · %s · %s', competition, round, status_short),
    IF(com_preco = partidas, 'SO_O_STATUS',
       IF(com_preco = 0, 'SEM_PRECO_COLETADO', 'MISTO')),
    CAST(partidas AS FLOAT64),
    CAST(com_preco AS FLOAT64),
    NULL,
    TO_JSON_STRING(STRUCT(competition, round, status_short, partidas, com_preco,
                          primeiro, ultimo))
FROM fora_do_universo

UNION ALL
SELECT 6, 'ordenacao',
    FORMAT('%s · piso %d', contraste, piso),
    veredito,
    rho,
    CAST(trocas_no_topo AS FLOAT64),
    CAST(trocas_de_sinal AS FLOAT64),
    TO_JSON_STRING(STRUCT(
        contraste, piso, n_premissas, sem_contraparte, sem_medida, quais_sem_contraparte,
        saiu_do_topo, entrou_no_topo, delta_dif_medio, max_delta_posto, n_medio_a, n_medio_b,
        0.9 AS regua_rho, 2 AS regua_topo,
        4 AS regua_sinal
    ))
FROM bloco_ordenacao

UNION ALL
SELECT 7, 'topo',
    FORMAT('%s · piso %d · %s', contraste, piso, premissa),
    direcao,
    CAST(pos_a AS FLOAT64),
    CAST(pos_b AS FLOAT64),
    peso_a,
    TO_JSON_STRING(STRUCT(contraste, piso, premissa, mercado, direcao,
                          pos_a, pos_b, peso_a, peso_b))
FROM bloco_topo

ORDER BY ordem, chave