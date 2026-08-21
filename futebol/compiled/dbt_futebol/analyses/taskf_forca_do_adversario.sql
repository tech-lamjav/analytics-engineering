/*
    [F-8] FORÇA DO ADVERSÁRIO — o primeiro dos dois confundidores do merge, medido em vez de
    registrado.

    O QUE ELE AMEAÇA. A célula `escopo` aumenta a amostra emprestando ao histórico de um time as
    partidas que ele jogou em OUTRA competição da mesma temporada. Se essas partidas emprestadas
    forem contra adversários de nível diferente, o ganho de amostra vem junto com um viés de
    nível: a média que decide se a aposta é boa passa a misturar jogo de Brasileirão com jogo de
    fase inicial de Copa do Brasil, e a premissa acende por um passado que descreve outro
    campeonato. É o confundidor que o ticket de origem não menciona e que a spec #49 acrescentou
    (user stories 21 e 22).

    O QUE ESTA ANÁLISE MEDE, e onde:

      (a) de ONDE vem cada partida emprestada — a competição de origem, por competição-âncora;
      (b) QUEM era o adversário naquela partida, em quatro categorias EXCLUDENTES e sem imputação:
          `na_base_com_ppg`, `na_base_sem_ppg`, `fora_da_base` e `selecao`;
      (c) o `ppg` PIT do adversário quando ele existe, nativo contra emprestado, e ao lado dele o
          `ppg` de LIGA do mesmo adversário — o mesmo número na mesma unidade, seja qual for a
          competição da partida;
      (d) a LIGA a que o adversário pertence, que é a única medida de nível que a base permite;
      (e) os gols pró/contra do próprio time nas duas origens — o canal por onde o viés chega às
          médias que as premissas leem.

    ⚠️ O QUE `ppg` ALCANÇA, E O QUE NÃO — E O `ppg_referencia` EXISTE PARA ISSO SER CONFERIDO, NÃO
    ACREDITADO. `ppg` é pontos por jogo DENTRO da competição. Numa competição de PONTOS CORRIDOS a
    média dele é quase constante por construção (o campeonato distribui 3 pontos por jogo decidido
    e 2 por empate), e medido é isso mesmo: 1,364 no Brasileirão e 1,333 na Série B. Ali `ppg` mede
    posição RELATIVA — se o adversário é de cima ou de baixo da tabela DELE — e é cego a diferença
    de NÍVEL entre competições.

    Em competição de MATA-MATA ele não mede nem isso. Quem perde é eliminado e para de jogar, então
    a população que chega à rodada seguinte é a dos que venceram: a média de `ppg` da Copa do Brasil
    é **2,609**, contra 1,438 da Libertadores (que tem fase de grupos e por isso volta a se
    comportar como liga). `ppg` alto numa copa de mata-mata é sobrevivência, não força. Comparar
    `ppg` de copa com `ppg` de liga como se fossem a mesma régua é o erro que esta análise existe
    para não cometer — o nível sai da COMPOSIÇÃO (de qual competição a partida veio, `nivel =
    'fonte'`) e do tamanho das categorias sem número, nunca do `ppg_medio` sozinho.

    ⚠️ `fora_da_base` NÃO É IMPUTADO. Um time está na base quando alguma competição de PONTOS
    CORRIDOS da coleta o alcança (`dim_leagues.league_type = 'League'`, derivado do dado e não de
    uma lista digitada). Não coletamos Série C nem D, então o adversário das fases iniciais da
    Copa do Brasil é invisível — e a medição mostrou que o buraco é maior do que a spec supôs: o
    clube sul-americano de Libertadores e de Sudamericana também está fora, porque não coletamos as
    ligas nacionais dele. Não há `ppg` de nenhum dos dois em lugar nenhum, e inventar um — média da
    competição, percentil, o que for — trocaria o achado por um número. A categoria fica explícita
    e o tamanho dela é o resultado.

    As outras duas categorias sem `ppg` são OUTRAS COISAS, e por isso não se juntam à primeira:

      `na_base_sem_ppg`  o adversário existe na base, mas naquele instante ainda não tinha partida
                         anterior na competição daquele jogo (rodada 1), então o PIT dele é NULL
                         por degradação graciosa. É ausência de passado, não ausência de coleta.
      `selecao`          adversário de Copa do Mundo. Seleção não tem liga a coletar — a ausência
                         é o formato do futebol de seleções, não um limite nosso.

    ⚠️ E É POR ISSO QUE EXISTE O NÍVEL `liga_do_adversario`, QUE É ONDE A RESPOSTA MORA. Nenhum
    `ppg` enxerga NÍVEL: o do PIT é relativo à competição da partida, e o `ppg_liga_medio` é
    relativo à liga do adversário — um time de Série B com 1,40 não vale o mesmo que um de Série A
    com 1,40. O que é observável sem inventar rating é a LIGA a que o adversário pertence, e é
    exatamente a variável do medo da spec ("emprestar jogos de uma competição mais forte para
    outra mais fraca"). Esse nível conta quantas partidas de cada origem foram contra time de cada
    liga, e o `gols_pro_medio`/`gols_contra_medio` ao lado mostra o que aquilo faz com a média que
    as premissas leem.

    ────────────────────────────────────────────────────────────────────────────────
    SEIS NÍVEIS NA MESMA SAÍDA, com a coluna `nivel` separando os grãos. Somar linhas de níveis
    diferentes conta a mesma partida mais de uma vez — filtre `nivel` sempre.

      conferencia         1 linha. A reconstrução aqui bate com o que o MODELO gravou?
      total               por `origem`, o universo inteiro.
      competicao          por (competição-âncora, `origem`).
      fonte               por (competição-âncora, competição da partida emprestada). Só emprestadas.
      liga_do_adversario  por (competição-âncora, liga do adversário, `origem`).
      ppg_referencia      por competição: a média de `ppg` de todo o PIT dela. É a régua de leitura
                          dos `ppg_medio` acima, não uma medição do universo.

    As colunas não querem dizer a mesma coisa nos seis níveis, e a legenda é esta:

      nível               chave / chave2                  partidas          adv_com_ppg
      ──────────────────  ──────────────────────────────  ────────────────  ──────────────────
      conferencia         —                               —                 —
      total               'TODAS'                         partidas do hist. adversários com ppg
      competicao          competição-âncora               idem              idem
      fonte               âncora / competição de origem   idem              idem
      liga_do_adversario  âncora / liga do adversário     idem              idem
      ppg_referencia      competição                      linhas do PIT     linhas do PIT com ppg

    `pares_batem_base`, `pares_batem_escopo` e `veredito` só existem no nível `conferencia`;
    `ppg_min`/`ppg_max` só no `ppg_referencia`. `jogos_no_universo` é o universo congelado inteiro
    na `conferencia` (o gabarito) e, nos demais níveis, as âncoras que têm pelo menos uma partida
    naquele estrato — os dois números diferem, e é assim que se enxerga quanto do universo o
    estrato alcança.

    ⚠️ O RÓTULO `fora_da_base` DO NÍVEL `liga_do_adversario` NÃO É A MESMA CONTAGEM DA COLUNA
    `adv_fora_da_base`, e a diferença é informação. A coluna é por BASE INTEIRA (o time tem liga
    em alguma temporada?); o rótulo é por TEMPORADA (o time tem liga NAQUELA temporada?). Medido:
    583 partidas com o rótulo contra 573 na coluna — 10 em 4.021, e são adversários que têm liga
    na base mas não em 2026. São 40 times nessa situação, quase todos rebaixados ou promovidos
    entre o backfill de 24/25 e agora (Amazonas, Brusque, Ferroviária, Burnley, Empoli...).

    ⚠️ POR QUE HÁ UMA CONFERÊNCIA, E POR QUE ELA É A PRIMEIRA LINHA. Esta análise RECONSTRÓI o
    join de histórico do int_futebol_team_form_pit em vez de ler um agregado pronto — precisa da
    partida individual, e o carimbo guarda só a contagem. Reconstrução é cópia, e cópia deriva do
    original em silêncio: bastaria esquecer o `l.season = a.season` para o número sair maior e com
    cara de certo. Então a reconstrução é cobrada contra o carimbo das células (`base` e `escopo`,
    #53), par a par: as partidas `nativa` têm de ser exatamente o `played_total` da `base`, e o
    total (nativa + emprestada) exatamente o da `escopo`. Se a linha `conferencia` não sair
    `EXATA`, nada abaixo dela significa o que diz.

    ⚠️ ESTA ANÁLISE NÃO DEPENDE DA CÉLULA MATERIALIZADA, e isso é escolha, não sorte. Ela lê três
    coisas do dataset: o UNIVERSO (invariante entre células — é a primeira invariante da Costura
    B, #55), o `ppg` do PIT (invariante por construção — a tabela do campeonato é sempre
    competição+temporada, ADR 0008; medido: 1.916 de 1.916 pares idênticos entre a produção e a
    célula `ambos`) e o CARIMBO, que tem as quatro células gravadas lado a lado. O `jogos_no_universo`
    sai na saída para ser conferido contra os 169 do gabarito.

    COMO RODAR (do dbt_futebol/), com o carimbo das células `base` e `escopo` já gravado:

      # dim_leagues e dim_teams não estavam no dataset de medição — a ancestria das células não
      # passa por elas. Uma vez só, e sem risco de tocar célula: nenhum dos seis nós de premissas
      # as referencia.
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt run --target taskF \
        --select dim_leagues stg_futebol_leagues dim_teams stg_futebol_teams

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_forca_do_adversario
      bq query --use_legacy_sql=false --max_rows=100000 --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_forca_do_adversario.sql

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
),tipo_competicao AS (
    SELECT DISTINCT league_id AS competition_id, league_type
    FROM `smartbetting-dados`.`futebol`.`dim_leagues`
),times_na_base AS (
    SELECT DISTINCT lados.team_id
    FROM (
        SELECT home_team_id AS team_id, competition_id FROM fixtures
        UNION ALL
        SELECT away_team_id,            competition_id FROM fixtures
    ) AS lados
    JOIN tipo_competicao AS t
      ON  t.competition_id = lados.competition_id
     AND  t.league_type    = 'League'
),team_log AS (
    SELECT competition_id, competition, season, kickoff_utc, fixture_id,
           home_team_id AS team_id, away_team_id AS oponente_id,
           goals_home   AS gf,      goals_away   AS ga
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
    UNION ALL
    SELECT competition_id, competition, season, kickoff_utc, fixture_id,
           away_team_id,            home_team_id,
           goals_away,              goals_home
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),ancoras AS (
    SELECT
        f.fixture_id, f.competition, f.competition_id, f.season, f.kickoff_utc,
        lado AS team_id
    FROM fixtures AS f
    JOIN universo USING (fixture_id)
    CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
),historico AS (
    SELECT
        a.fixture_id     AS ancora_fixture_id,
        a.competition    AS ancora_competition,
        a.team_id,
        l.fixture_id     AS hist_fixture_id,
        l.competition    AS hist_competition,
        l.kickoff_utc    AS hist_kickoff_utc,
        l.season         AS hist_season,
        l.oponente_id,
        l.gf,
        l.ga,
        IF(l.competition_id = a.competition_id, 'nativa', 'emprestada') AS origem
    FROM ancoras AS a
    JOIN team_log AS l
      ON  l.team_id     = a.team_id
      AND l.season      = a.season
      AND l.kickoff_utc < a.kickoff_utc
),

liga_do_adversario AS (
    SELECT team_id, season, liga
    FROM (
        SELECT
            lado          AS team_id,
            f.season,
            f.competition AS liga,
            COUNT(*)      AS n_jogos
        FROM fixtures AS f
        CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
        JOIN tipo_competicao AS tc
          ON  tc.competition_id = f.competition_id
         AND  tc.league_type    = 'League'
        GROUP BY lado, f.season, f.competition
    )QUALIFY ROW_NUMBER() OVER (
        PARTITION BY team_id, season ORDER BY n_jogos DESC, liga
    ) = 1
),

adv_ppg_de_liga AS (
    SELECT
        h.ancora_fixture_id,
        h.team_id,
        h.hist_fixture_id,
        SAFE_DIVIDE(
            SUM(CASE WHEN l.gf > l.ga THEN 3 WHEN l.gf = l.ga THEN 1 ELSE 0 END),
            COUNT(*)
        ) AS ppg_liga
    FROM historico AS h
    JOIN team_log AS l
      ON  l.team_id     = h.oponente_id
      AND l.season      = h.hist_season
      AND l.kickoff_utc < h.hist_kickoff_utc
    JOIN tipo_competicao AS tc
      ON  tc.competition_id = l.competition_id
     AND  tc.league_type    = 'League'
    GROUP BY h.ancora_fixture_id, h.team_id, h.hist_fixture_id
),historico_classificado AS (
    SELECT
        h.*,
        p.ppg      AS adv_ppg,
        pl.ppg_liga AS adv_ppg_liga,
        COALESCE(la.liga, IF(dt.national, 'selecao', 'fora_da_base')) AS adv_liga,
        CASE
            WHEN dt.national       THEN 'selecao'
            WHEN b.team_id IS NULL THEN 'fora_da_base'
            WHEN p.ppg     IS NULL THEN 'na_base_sem_ppg'
            ELSE                        'na_base_com_ppg'
        END AS categoria_adversario
    FROM historico AS h
    LEFT JOIN times_na_base AS b
           ON b.team_id = h.oponente_id
    LEFT JOIN `smartbetting-dados`.`futebol`.`dim_teams` AS dt
           ON dt.team_id = h.oponente_id
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS p
           ON  p.fixture_id = h.hist_fixture_id
          AND  p.team_id    = h.oponente_id
    LEFT JOIN adv_ppg_de_liga AS pl
           ON  pl.ancora_fixture_id = h.ancora_fixture_id
          AND  pl.team_id           = h.team_id
          AND  pl.hist_fixture_id   = h.hist_fixture_id
    LEFT JOIN liga_do_adversario AS la
           ON  la.team_id = h.oponente_id
          AND  la.season  = h.hist_season
),

-- ─────────────────────────── conferência contra o carimbo ───────────────────────────

contagem_reconstruida AS (
    SELECT
        a.fixture_id,
        a.team_id,
        COUNTIF(h.origem = 'nativa') AS n_nativa,
        COUNT(h.origem)              AS n_total
    FROM ancoras AS a
    LEFT JOIN historico AS h
           ON  h.ancora_fixture_id = a.fixture_id
          AND  h.team_id           = a.team_id
    GROUP BY a.fixture_id, a.team_id
),

conferencia AS (
    SELECT(SELECT COUNT(DISTINCT fixture_id) FROM ancoras) AS jogos_no_universo,
        COUNT(*)                                  AS pares,
        COUNTIF(c.n_nativa = b.played_total)      AS pares_batem_base,
        COUNTIF(c.n_total  = e.played_total)      AS pares_batem_escopo
    FROM contagem_reconstruida AS c
    JOIN (SELECT fixture_id, team_id, played_total FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula` WHERE celula = 'base')   AS b
      USING (fixture_id, team_id)
    JOIN (SELECT fixture_id, team_id, played_total FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula` WHERE celula = 'escopo') AS e
      USING (fixture_id, team_id)
),

-- ─────────────────────────── os agregados ───────────────────────────



por_total AS (
    SELECT origem, 
        COUNT(*)                                                             AS partidas,
        COUNT(DISTINCT FORMAT('%d-%d', ancora_fixture_id, team_id))          AS pares,
        COUNT(DISTINCT ancora_fixture_id)                                    AS jogos_no_universo,
        COUNTIF(categoria_adversario = 'na_base_com_ppg')                    AS adv_com_ppg,
        COUNTIF(categoria_adversario = 'na_base_sem_ppg')                    AS adv_sem_ppg,
        COUNTIF(categoria_adversario = 'fora_da_base')                       AS adv_fora_da_base,
        COUNTIF(categoria_adversario = 'selecao')                            AS adv_selecao,
        COUNTIF(adv_ppg_liga IS NOT NULL)                                    AS adv_com_ppg_liga,
        ROUND(AVG(adv_ppg), 3)                                               AS ppg_medio,
        
    ROUND(
        ARRAY_AGG(adv_ppg IGNORE NULLS ORDER BY adv_ppg)
            [SAFE_OFFSET(DIV(COUNTIF((adv_ppg) IS NOT NULL) - 1, 2))],
        3)                                       AS ppg_mediana,
        ROUND(AVG(adv_ppg_liga), 3)                                          AS ppg_liga_medio,ROUND(SAFE_DIVIDE(SUM(gf), COUNT(*)), 3)                             AS gols_pro_medio,
        ROUND(SAFE_DIVIDE(SUM(ga), COUNT(*)), 3)                             AS gols_contra_medio
    FROM historico_classificado
    GROUP BY ROLLUP(origem)
),

por_competicao AS (
    SELECT ancora_competition, origem, 
        COUNT(*)                                                             AS partidas,
        COUNT(DISTINCT FORMAT('%d-%d', ancora_fixture_id, team_id))          AS pares,
        COUNT(DISTINCT ancora_fixture_id)                                    AS jogos_no_universo,
        COUNTIF(categoria_adversario = 'na_base_com_ppg')                    AS adv_com_ppg,
        COUNTIF(categoria_adversario = 'na_base_sem_ppg')                    AS adv_sem_ppg,
        COUNTIF(categoria_adversario = 'fora_da_base')                       AS adv_fora_da_base,
        COUNTIF(categoria_adversario = 'selecao')                            AS adv_selecao,
        COUNTIF(adv_ppg_liga IS NOT NULL)                                    AS adv_com_ppg_liga,
        ROUND(AVG(adv_ppg), 3)                                               AS ppg_medio,
        
    ROUND(
        ARRAY_AGG(adv_ppg IGNORE NULLS ORDER BY adv_ppg)
            [SAFE_OFFSET(DIV(COUNTIF((adv_ppg) IS NOT NULL) - 1, 2))],
        3)                                       AS ppg_mediana,
        ROUND(AVG(adv_ppg_liga), 3)                                          AS ppg_liga_medio,ROUND(SAFE_DIVIDE(SUM(gf), COUNT(*)), 3)                             AS gols_pro_medio,
        ROUND(SAFE_DIVIDE(SUM(ga), COUNT(*)), 3)                             AS gols_contra_medio
    FROM historico_classificado
    GROUP BY ROLLUP(ancora_competition, origem)
    HAVING ancora_competition IS NOT NULL
),

por_fonte AS (
    SELECT ancora_competition, hist_competition, 
        COUNT(*)                                                             AS partidas,
        COUNT(DISTINCT FORMAT('%d-%d', ancora_fixture_id, team_id))          AS pares,
        COUNT(DISTINCT ancora_fixture_id)                                    AS jogos_no_universo,
        COUNTIF(categoria_adversario = 'na_base_com_ppg')                    AS adv_com_ppg,
        COUNTIF(categoria_adversario = 'na_base_sem_ppg')                    AS adv_sem_ppg,
        COUNTIF(categoria_adversario = 'fora_da_base')                       AS adv_fora_da_base,
        COUNTIF(categoria_adversario = 'selecao')                            AS adv_selecao,
        COUNTIF(adv_ppg_liga IS NOT NULL)                                    AS adv_com_ppg_liga,
        ROUND(AVG(adv_ppg), 3)                                               AS ppg_medio,
        
    ROUND(
        ARRAY_AGG(adv_ppg IGNORE NULLS ORDER BY adv_ppg)
            [SAFE_OFFSET(DIV(COUNTIF((adv_ppg) IS NOT NULL) - 1, 2))],
        3)                                       AS ppg_mediana,
        ROUND(AVG(adv_ppg_liga), 3)                                          AS ppg_liga_medio,ROUND(SAFE_DIVIDE(SUM(gf), COUNT(*)), 3)                             AS gols_pro_medio,
        ROUND(SAFE_DIVIDE(SUM(ga), COUNT(*)), 3)                             AS gols_contra_medio
    FROM historico_classificado
    WHERE origem = 'emprestada'
    GROUP BY ancora_competition, hist_competition
),

por_liga_do_adversario AS (
    SELECT ancora_competition, origem, adv_liga, 
        COUNT(*)                                                             AS partidas,
        COUNT(DISTINCT FORMAT('%d-%d', ancora_fixture_id, team_id))          AS pares,
        COUNT(DISTINCT ancora_fixture_id)                                    AS jogos_no_universo,
        COUNTIF(categoria_adversario = 'na_base_com_ppg')                    AS adv_com_ppg,
        COUNTIF(categoria_adversario = 'na_base_sem_ppg')                    AS adv_sem_ppg,
        COUNTIF(categoria_adversario = 'fora_da_base')                       AS adv_fora_da_base,
        COUNTIF(categoria_adversario = 'selecao')                            AS adv_selecao,
        COUNTIF(adv_ppg_liga IS NOT NULL)                                    AS adv_com_ppg_liga,
        ROUND(AVG(adv_ppg), 3)                                               AS ppg_medio,
        
    ROUND(
        ARRAY_AGG(adv_ppg IGNORE NULLS ORDER BY adv_ppg)
            [SAFE_OFFSET(DIV(COUNTIF((adv_ppg) IS NOT NULL) - 1, 2))],
        3)                                       AS ppg_mediana,
        ROUND(AVG(adv_ppg_liga), 3)                                          AS ppg_liga_medio,ROUND(SAFE_DIVIDE(SUM(gf), COUNT(*)), 3)                             AS gols_pro_medio,
        ROUND(SAFE_DIVIDE(SUM(ga), COUNT(*)), 3)                             AS gols_contra_medio
    FROM historico_classificado
    GROUP BY ancora_competition, origem, adv_liga
),ppg_referencia AS (
    SELECT
        p.competition,
        COUNT(*)                        AS linhas_do_pit,
        COUNTIF(p.ppg IS NOT NULL)      AS linhas_com_ppg,
        ROUND(AVG(p.ppg), 3)            AS ppg_medio,
        ROUND(MIN(p.ppg), 3)            AS ppg_min,
        ROUND(MAX(p.ppg), 3)            AS ppg_max
    FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS p
    WHERE p.season IN (SELECT DISTINCT season FROM ancoras)
      AND p.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')
    GROUP BY p.competition
),

-- ─────────────────────────── empilhamento ───────────────────────────

empilhado AS (
    SELECT
        'conferencia'         AS nivel,
        0                     AS nivel_ord,
        CAST(NULL AS STRING)  AS chave,
        CAST(NULL AS STRING)  AS chave2,
        CAST(NULL AS STRING)  AS origem,
        CAST(NULL AS INT64)   AS partidas,
        pares,
        jogos_no_universo,
        CAST(NULL AS INT64)   AS adv_com_ppg,
        CAST(NULL AS INT64)   AS adv_sem_ppg,
        CAST(NULL AS INT64)   AS adv_fora_da_base,
        CAST(NULL AS INT64)   AS adv_selecao,
        CAST(NULL AS INT64)   AS adv_com_ppg_liga,
        CAST(NULL AS FLOAT64) AS ppg_medio,
        CAST(NULL AS FLOAT64) AS ppg_mediana,
        CAST(NULL AS FLOAT64) AS ppg_liga_medio,
        CAST(NULL AS FLOAT64) AS ppg_min,
        CAST(NULL AS FLOAT64) AS ppg_max,
        CAST(NULL AS FLOAT64) AS gols_pro_medio,
        CAST(NULL AS FLOAT64) AS gols_contra_medio,
        pares_batem_base,
        pares_batem_escopo,IF(pares = pares_batem_base
             AND pares = pares_batem_escopo
             AND pares = 2 * jogos_no_universo,
           'EXATA',
           'DIVERGENTE — nada abaixo desta linha significa o que diz') AS veredito
    FROM conferencia

    UNION ALL

    SELECT
        'total', 1, 'TODAS', CAST(NULL AS STRING), COALESCE(origem, 'TODAS'),
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_total

    UNION ALL

    SELECT
        'competicao', 2, ancora_competition, CAST(NULL AS STRING), COALESCE(origem, 'TODAS'),
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_competicao

    UNION ALL

    SELECT
        'fonte', 3, ancora_competition, hist_competition, 'emprestada',
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_fonte

    UNION ALL

    SELECT
        'liga_do_adversario', 4, ancora_competition, adv_liga, origem,
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_liga_do_adversario

    UNION ALL

    SELECT
        'ppg_referencia', 5, competition, CAST(NULL AS STRING), CAST(NULL AS STRING),
        linhas_do_pit, CAST(NULL AS INT64), CAST(NULL AS INT64),
        linhas_com_ppg, CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS INT64),
        ppg_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), ppg_min, ppg_max,
        CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM ppg_referencia
)

SELECT
    nivel,
    chave,
    chave2,
    origem,
    partidas,
    pares,
    jogos_no_universo,
    adv_com_ppg,
    adv_sem_ppg,
    adv_fora_da_base,
    adv_selecao,
    adv_com_ppg_liga,
    ROUND(SAFE_DIVIDE(adv_fora_da_base, partidas) * 100, 1) AS pct_fora_da_base,
    ROUND(SAFE_DIVIDE(adv_selecao,      partidas) * 100, 1) AS pct_selecao,
    ppg_medio,
    ppg_mediana,
    ppg_liga_medio,
    ppg_min,
    ppg_max,
    gols_pro_medio,
    gols_contra_medio,
    pares_batem_base,
    pares_batem_escopo,
    veredito
FROM empilhado
ORDER BY nivel_ord, chave, chave2, origem