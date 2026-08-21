/*
    [F-5] AS DUAS CONTAGENS DE AMOSTRA, CONFERIDAS — e as invariantes que o eixo de RECORTE traz.

    O critério de aceite da #54 diz "sob janela de contagem, o `usado` satura no tamanho da janela
    e o `disponível` não — VERIFICADO, NÃO ASSUMIDO". Esta análise é a verificação. Ela também
    fecha, para o eixo de recorte, o mesmo buraco que a analyses/taskf_monotonicidade_escopo.sql
    fecha para o eixo de escopo — aquela lê os literais `base`/`escopo` e não alcança as duas
    células novas.

    ────────────────────────────────────────────────────────────────────────────────
    QUATRO BLOCOS, QUATRO PERGUNTAS DIFERENTES. Cada linha da saída traz o seu veredito.

    `saturacao` — uma linha por célula. A identidade que define as duas contagens:

        recorte `temporada`   usado = disponível          (não há teto: tudo que existe é usado)
        recorte `ultimos_10`  usado = LEAST(disponível, N)

      Nas células com teto, `pares_saturados` (disponível > usado) tem de ser MAIOR QUE ZERO: é a
      guarda de não-vacuidade. Zero saturação numa célula rotulada `ultimos_10` não quer dizer
      "ninguém tinha mais de N partidas" — com dezenas de times de 20+ jogos na base, quer dizer
      que o dado gravado sob esse rótulo é de outra célula, porque o carimbo rodou fora de ordem.
      É o mesmo modo de falha que o `MESMO_CONTEUDO_NAS_DUAS` da análise de escopo pega.

      ⚠️ NAS DUAS CÉLULAS DE RECORTE `temporada` ESTE BLOCO NÃO É EVIDÊNCIA SOBRE O DADO, e o OK
      delas não deve ser lido como se fosse. O modelo não emite `played_total_disponivel` no
      default (emiti-la mudaria o SQL compilado do caminho que produção usa), então o carimbo
      projeta o próprio `played_total` na coluna do disponível — e `usado = disponível` ali é
      verdade por construção, não medição. O que essas duas linhas ainda checam de verdade é o
      RÓTULO: uma célula de `temporada` gravada com o rótulo `ultimos_10` passaria a ser cobrada
      pela identidade com teto e cairia, já que o disponível dela chega a 37 e 60. A medição
      propriamente dita são as duas células com teto, onde as duas colunas vêm de contas
      diferentes do modelo.

    `piso` — uma linha por célula, sobre os jogos AVALIADOS do universo congelado (os 169, e não
      todos os fixtures da janela — ver o CTE `fixtures_do_universo`). Cortar no disponível e
      cortar no usado dão o MESMO conjunto de jogos, em todos os pisos varridos. É consequência da identidade acima (para piso <= N,
      `LEAST(d, N) >= piso` ⟺ `d >= piso`), mas o cabeçalho do Teste 2 afirma isso ao leitor e
      afirmação sem número é o que esta task existe para não fazer. Se um dia a varredura ganhar
      um piso MAIOR que N, este bloco fica vermelho — e aí a escolha de cortar no disponível
      deixa de ser inócua e passa a ser a única correta.

    `monotonicidade` — uma linha por par de células. Os quatro pares do 2x2 em que soltar uma
      dimensão só pode ACRESCENTAR partidas anteriores:

        base    → recorte   (solta a temporada, mantém a competição)
        escopo  → ambos     (solta a temporada, com a competição já solta)
        base    → escopo    (solta a competição, mantém a temporada — a da #53, refeita)
        recorte → ambos     (solta a competição, com a temporada já solta)

      ⚠️ O PAR `base` → `escopo` TAMBÉM É MEDIDO PELA analyses/taskf_monotonicidade_escopo.sql,
      e a repetição é deliberada. Aqui ele é a quarta aresta do 2x2 — tirá-lo deixaria a tabela
      com três linhas e faria uma das quatro afirmações depender de outro arquivo, que é pior de
      ler do que a repetição. Os dois não são cópia um do outro: aquele compara `played_total` e
      confere o lado `base` contra o baseline congelado nas partições de insumo casado; este
      compara o `disponível` das quatro células entre si. Nas células de `temporada` as duas
      colunas são o mesmo número, então os dois TÊM de dar o mesmo resultado — e dão, exatamente
      (6.434 pares com ganho, 8,13 de ganho médio, 48 de máximo, 0 violações). Divergirem é sinal,
      não ruído.

      ⚠️ A comparação é sobre o DISPONÍVEL, e tem de ser. No usado ela seria falsa por desenho: um
      time com 25 jogos na temporada tem `base` = 25 e `recorte` usado = 10, e isso é o teto
      funcionando, não perda de histórico. Medir monotonicidade na contagem que satura acusaria
      violação em cima do próprio mecanismo que se quis medir.

    `chaves` — uma linha só. O conjunto de pares (jogo, time) é IDÊNTICO nas quatro células. Os
      eixos mexem no histórico que cada par carrega, nunca em quais pares existem; divergência
      aqui é fan-out ou perda de linha, e as guardas de grão dos modelos pegam só o primeiro.

    ────────────────────────────────────────────────────────────────────────────────
    ⚠️ ESTA ANÁLISE NÃO CHAMA taskf_celula(). Ela lê os quatro nomes da tabela de carimbos, pelo
    mesmo motivo da análise de escopo: é uma comparação ENTRE células e não pertence a nenhuma
    delas. Depender das vars da linha de comando seria exatamente o acoplamento que ela audita.
    O que ela lê de macro é o tamanho do recorte e a lista de pisos — constantes, não vars, e as
    MESMAS que os modelos e o Teste 2 leem.

    POR QUE ANÁLISE E NÃO TESTE SINGULAR: idem. Um teste dbt roda dentro da execução de UMA
    célula e as outras três ainda não existem. As invariantes sobre as quatro juntas são a Costura
    B (#55), por decisão da spec.

    COMO RODAR (do dbt_futebol/), depois de as QUATRO células terem sido carimbadas:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_saturacao_recorte
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_saturacao_recorte.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    ⚠️ O QUE ELA NÃO FAZ: comparar o número das premissas entre células. Isso é o
    analyses/taskf_delta_celulas.sql, que aceita qualquer par dos quatro nomes. Aqui só se
    verifica que as contagens que aquele número usa significam a mesma coisa nas quatro.

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

,fixtures_do_universo AS (
    SELECT DISTINCT fixture_id
    FROM apostas
    WHERE (kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00'))
),

cel AS (
    SELECT
        celula,
        pit_recorte,
        fixture_id,
        team_id,
        competition,
        kickoff_utc,
        played_total            AS usado,
        played_total_disponivel AS disp,
        medido_em,
        git_sha
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula`
),

-- ── saturacao ───────────────────────────────────────────────────────────────────────────────
saturacao AS (
    SELECT
        celula,
        ANY_VALUE(pit_recorte)                                       AS pit_recorte,
        COUNT(*)                                                     AS pares,
        MAX(usado)                                                   AS max_usado,
        MAX(disp)                                                    AS max_disp,
        COUNTIF(disp > usado)                                        AS pares_saturados,
        COUNTIF(disp > 10)                                      AS pares_acima_do_teto,
        COUNTIF(usado != IF(pit_recorte = 'ultimos_10',
                            LEAST(disp, 10), disp))             AS quebra_da_identidade,
        ROUND(AVG(usado), 2)                                         AS usado_medio,
        ROUND(AVG(disp),  2)                                         AS disp_medio,
        MIN(medido_em)                                               AS medido_em,
        ANY_VALUE(git_sha)                                           AS git_sha
    FROM cel
    GROUP BY celula
),

-- ── piso ────────────────────────────────────────────────────────────────────────────────────
por_jogo AS (
    SELECT
        celula,
        fixture_id,
        MIN(usado) AS min_usado,
        MIN(disp)  AS min_disp
    FROM cel
    JOIN fixtures_do_universo USING (fixture_id)
    GROUP BY celula, fixture_id
),

piso AS (
    SELECT
        celula,
        COUNT(*) AS jogos,
        COUNTIF(min_disp  >= 0) AS jogos_disp_p0,
        COUNTIF(min_usado >= 0) AS jogos_usado_p0,
        COUNTIF(min_disp  >= 3) AS jogos_disp_p3,
        COUNTIF(min_usado >= 3) AS jogos_usado_p3,
        COUNTIF(min_disp  >= 5) AS jogos_disp_p5,
        COUNTIF(min_usado >= 5) AS jogos_usado_p5,
        COUNTIF(min_disp  >= 10) AS jogos_disp_p10,
        COUNTIF(min_usado >= 10) AS jogos_usado_p10,
        (IF(COUNTIF(min_disp >= 0) != COUNTIF(min_usado >= 0), 1, 0)
          + IF(COUNTIF(min_disp >= 3) != COUNTIF(min_usado >= 3), 1, 0)
          + IF(COUNTIF(min_disp >= 5) != COUNTIF(min_usado >= 5), 1, 0)
          + IF(COUNTIF(min_disp >= 10) != COUNTIF(min_usado >= 10), 1, 0)
          ) AS pisos_divergentes
    FROM por_jogo
    GROUP BY celula
),

-- ── monotonicidade ──────────────────────────────────────────────────────────────────────────
mono_base_recorte AS (
    SELECT
        'base -> recorte'                       AS item,
        COUNTIF(a.disp IS NOT NULL)                        AS pares_esq,
        COUNTIF(b.disp IS NOT NULL)                        AS pares_dir,
        COUNTIF(a.disp IS NULL OR b.disp IS NULL)          AS chaves_divergentes,
        COUNTIF(b.disp < a.disp)                           AS violacoes,
        COUNTIF(b.disp > a.disp)                           AS pares_com_ganho,
        ROUND(AVG(IF(b.disp > a.disp, b.disp - a.disp, NULL)), 2) AS ganho_medio_quando_ganha,
        MAX(b.disp - a.disp)                               AS ganho_max,
        ARRAY_AGG(
            IF(b.disp < a.disp,
               TO_JSON_STRING(STRUCT(a.fixture_id, a.team_id, a.competition,
                                     a.disp AS disp_esq, b.disp AS disp_dir)),
               NULL)
            IGNORE NULLS LIMIT 3
        )                                                  AS exemplos
    FROM (SELECT * FROM cel WHERE celula = 'base') AS a
    FULL OUTER JOIN (SELECT * FROM cel WHERE celula = 'recorte') AS b
        USING (fixture_id, team_id)
),
mono_escopo_ambos AS (
    SELECT
        'escopo -> ambos'                       AS item,
        COUNTIF(a.disp IS NOT NULL)                        AS pares_esq,
        COUNTIF(b.disp IS NOT NULL)                        AS pares_dir,
        COUNTIF(a.disp IS NULL OR b.disp IS NULL)          AS chaves_divergentes,
        COUNTIF(b.disp < a.disp)                           AS violacoes,
        COUNTIF(b.disp > a.disp)                           AS pares_com_ganho,
        ROUND(AVG(IF(b.disp > a.disp, b.disp - a.disp, NULL)), 2) AS ganho_medio_quando_ganha,
        MAX(b.disp - a.disp)                               AS ganho_max,
        ARRAY_AGG(
            IF(b.disp < a.disp,
               TO_JSON_STRING(STRUCT(a.fixture_id, a.team_id, a.competition,
                                     a.disp AS disp_esq, b.disp AS disp_dir)),
               NULL)
            IGNORE NULLS LIMIT 3
        )                                                  AS exemplos
    FROM (SELECT * FROM cel WHERE celula = 'escopo') AS a
    FULL OUTER JOIN (SELECT * FROM cel WHERE celula = 'ambos') AS b
        USING (fixture_id, team_id)
),
mono_base_escopo AS (
    SELECT
        'base -> escopo'                       AS item,
        COUNTIF(a.disp IS NOT NULL)                        AS pares_esq,
        COUNTIF(b.disp IS NOT NULL)                        AS pares_dir,
        COUNTIF(a.disp IS NULL OR b.disp IS NULL)          AS chaves_divergentes,
        COUNTIF(b.disp < a.disp)                           AS violacoes,
        COUNTIF(b.disp > a.disp)                           AS pares_com_ganho,
        ROUND(AVG(IF(b.disp > a.disp, b.disp - a.disp, NULL)), 2) AS ganho_medio_quando_ganha,
        MAX(b.disp - a.disp)                               AS ganho_max,
        ARRAY_AGG(
            IF(b.disp < a.disp,
               TO_JSON_STRING(STRUCT(a.fixture_id, a.team_id, a.competition,
                                     a.disp AS disp_esq, b.disp AS disp_dir)),
               NULL)
            IGNORE NULLS LIMIT 3
        )                                                  AS exemplos
    FROM (SELECT * FROM cel WHERE celula = 'base') AS a
    FULL OUTER JOIN (SELECT * FROM cel WHERE celula = 'escopo') AS b
        USING (fixture_id, team_id)
),
mono_recorte_ambos AS (
    SELECT
        'recorte -> ambos'                       AS item,
        COUNTIF(a.disp IS NOT NULL)                        AS pares_esq,
        COUNTIF(b.disp IS NOT NULL)                        AS pares_dir,
        COUNTIF(a.disp IS NULL OR b.disp IS NULL)          AS chaves_divergentes,
        COUNTIF(b.disp < a.disp)                           AS violacoes,
        COUNTIF(b.disp > a.disp)                           AS pares_com_ganho,
        ROUND(AVG(IF(b.disp > a.disp, b.disp - a.disp, NULL)), 2) AS ganho_medio_quando_ganha,
        MAX(b.disp - a.disp)                               AS ganho_max,
        ARRAY_AGG(
            IF(b.disp < a.disp,
               TO_JSON_STRING(STRUCT(a.fixture_id, a.team_id, a.competition,
                                     a.disp AS disp_esq, b.disp AS disp_dir)),
               NULL)
            IGNORE NULLS LIMIT 3
        )                                                  AS exemplos
    FROM (SELECT * FROM cel WHERE celula = 'recorte') AS a
    FULL OUTER JOIN (SELECT * FROM cel WHERE celula = 'ambos') AS b
        USING (fixture_id, team_id)
),

-- ── chaves ──────────────────────────────────────────────────────────────────────────────────
chaves AS (
    SELECT
        COUNT(DISTINCT celula)                                     AS celulas,
        COUNT(*)                                                   AS linhas,
        COUNT(DISTINCT FORMAT('%d|%d', fixture_id, team_id))       AS pares_distintos,
        MIN(pares_por_celula)                                      AS min_pares_por_celula,
        MAX(pares_por_celula)                                      AS max_pares_por_celula
    FROM (
        SELECT celula, fixture_id, team_id,
               COUNT(*) OVER (PARTITION BY celula) AS pares_por_celula
        FROM cel
    )
)

SELECT 1 AS ordem, 'saturacao' AS bloco, celula AS item,
    CASE
        WHEN quebra_da_identidade > 0                             THEN 'IDENTIDADE_QUEBRADA'
        WHEN pit_recorte = 'ultimos_10' AND max_usado > 10   THEN 'USADO_ACIMA_DO_TETO'
        WHEN pit_recorte = 'ultimos_10' AND pares_saturados = 0   THEN 'SEM_SATURACAO_NENHUMA'
        WHEN pit_recorte = 'ultimos_10' AND max_disp <= 10   THEN 'DISPONIVEL_TAMBEM_SATUROU'
        WHEN pit_recorte = 'temporada'  AND pares_saturados > 0   THEN 'TETO_ONDE_NAO_DEVIA'
        ELSE                                                           'OK'
    END AS veredito,
    pares AS n_esq, pares_saturados AS n_dir, quebra_da_identidade AS divergencias,
    TO_JSON_STRING(STRUCT(pit_recorte, max_usado, max_disp, pares_acima_do_teto,
                          usado_medio, disp_medio, medido_em, git_sha)) AS numeros
FROM saturacao

UNION ALL

SELECT 2, 'piso', celula,
    IF(pisos_divergentes = 0, 'OK', 'PISO_CORTA_DIFERENTE'),
    jogos, jogos_disp_p5, pisos_divergentes,
    TO_JSON_STRING(STRUCT(
        jogos_disp_p0, jogos_usado_p0,
        jogos_disp_p3, jogos_usado_p3,
        jogos_disp_p5, jogos_usado_p5,
        jogos_disp_p10, jogos_usado_p10
    ))
FROM piso

UNION ALL

SELECT 3, 'monotonicidade', item,
    CASE
        WHEN chaves_divergentes > 0 THEN 'CHAVES_DIVERGENTES'
        WHEN violacoes > 0          THEN 'VIOLACAO_DE_MONOTONICIDADE'
        WHEN pares_com_ganho = 0    THEN 'MESMO_CONTEUDO_NAS_DUAS'
        ELSE                             'OK'
    END,
    pares_esq, pares_dir, violacoes,
    TO_JSON_STRING(STRUCT(chaves_divergentes, pares_com_ganho, ganho_medio_quando_ganha,
                          ganho_max, exemplos))
FROM mono_base_recorte

UNION ALL

SELECT 3, 'monotonicidade', item,
    CASE
        WHEN chaves_divergentes > 0 THEN 'CHAVES_DIVERGENTES'
        WHEN violacoes > 0          THEN 'VIOLACAO_DE_MONOTONICIDADE'
        WHEN pares_com_ganho = 0    THEN 'MESMO_CONTEUDO_NAS_DUAS'
        ELSE                             'OK'
    END,
    pares_esq, pares_dir, violacoes,
    TO_JSON_STRING(STRUCT(chaves_divergentes, pares_com_ganho, ganho_medio_quando_ganha,
                          ganho_max, exemplos))
FROM mono_escopo_ambos

UNION ALL

SELECT 3, 'monotonicidade', item,
    CASE
        WHEN chaves_divergentes > 0 THEN 'CHAVES_DIVERGENTES'
        WHEN violacoes > 0          THEN 'VIOLACAO_DE_MONOTONICIDADE'
        WHEN pares_com_ganho = 0    THEN 'MESMO_CONTEUDO_NAS_DUAS'
        ELSE                             'OK'
    END,
    pares_esq, pares_dir, violacoes,
    TO_JSON_STRING(STRUCT(chaves_divergentes, pares_com_ganho, ganho_medio_quando_ganha,
                          ganho_max, exemplos))
FROM mono_base_escopo

UNION ALL

SELECT 3, 'monotonicidade', item,
    CASE
        WHEN chaves_divergentes > 0 THEN 'CHAVES_DIVERGENTES'
        WHEN violacoes > 0          THEN 'VIOLACAO_DE_MONOTONICIDADE'
        WHEN pares_com_ganho = 0    THEN 'MESMO_CONTEUDO_NAS_DUAS'
        ELSE                             'OK'
    END,
    pares_esq, pares_dir, violacoes,
    TO_JSON_STRING(STRUCT(chaves_divergentes, pares_com_ganho, ganho_medio_quando_ganha,
                          ganho_max, exemplos))
FROM mono_recorte_ambos

UNION ALL

SELECT 4, 'chaves', 'as quatro celulas',
    CASE
        WHEN celulas < 4                                   THEN 'FALTA_CELULA'
        WHEN min_pares_por_celula != max_pares_por_celula  THEN 'CONTAGEM_DIFERENTE_ENTRE_CELULAS'
        WHEN pares_distintos != min_pares_por_celula       THEN 'CONJUNTO_DE_PARES_DIFERENTE'
        ELSE                                                    'OK'
    END,
    pares_distintos, linhas, IF(pares_distintos * celulas = linhas, 0, 1),
    TO_JSON_STRING(STRUCT(celulas, min_pares_por_celula, max_pares_por_celula))
FROM chaves

ORDER BY ordem, item