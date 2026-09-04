/*
    [F-10] O ENTREGÁVEL DA TASK [F]: as 39 linhas que o ticket de origem pediu, uma por premissa,
    no benchmark preferido de cada mercado — mais o anexo com as linhas de benchmark não-preferido,
    marcadas como não usadas para peso.

    ────────────────────────────────────────────────────────────────────────────────
    AS QUATRO COLUNAS DO TICKET, E DE ONDE CADA UMA SAI

      1. de onde puxa o histórico            `fonte`, `predicado`     declaração (macro)
      2. se a janela é limitada à competição  `escopo_hoje`            declaração (macro)
      3. se dá para juntar, e o que impede    `juntavel`,`impedimento` declaração (macro)
      4. o que o número vira                  as colunas `_hoje`/`_junto`   MEDIÇÃO

    Mais a quebra por FAMÍLIA de competição, que a spec #49 pede como coluna adicional.

    As três primeiras são leitura de código e moram em macros/taskf_fontes_de_historico.sql, com
    a validação de cobertura em tempo de compilação. A quarta sai da tabela acumulativa das quatro
    células (futebol_taskF.taskf_teste2), no par que responde à pergunta literal do ticket —
    "juntar os campeonatos" é o eixo de ESCOPO:

        `base`   escopo na competição do jogo   = o que roda hoje
        `escopo` escopo em todas as competições = o histórico junto

    O 2×2 completo (com o eixo de recorte) e a atribuição por eixo já estão publicados nas seções
    das #53 e #54 do docs/TASKF_RESULTADOS.md; esta análise não os repete.

    ⚠️ ESTA ANÁLISE NÃO MEDE NADA — ELA LÊ. Nenhuma célula é reconstruída aqui, e não deve ser:
    as quatro saíram da mesma execução (#58) e um rebuild hoje produziria um lote novo, quebrando
    a invariante que torna o 2×2 comparável. `dbt compile` + `bq query`, e nada de `dbt build`.

    ────────────────────────────────────────────────────────────────────────────────
    A DECLARAÇÃO É CONFRONTADA COM A MEDIÇÃO, e é isso que separa esta tabela de uma opinião
    bem formatada. Duas conferências, ambas na saída:

      `cobertura`     a declaração e a medição cobrem o MESMO conjunto de premissas. A macro já
                      confere isso contra futebol_insumos_premissa() ao compilar; aqui a
                      contraparte é o que a medição REALMENTE produziu, que é outra coisa — uma
                      premissa que não acende nenhuma vez some do taskf_teste2 (o `HAVING` dele)
                      e sairia como `SEM_MEDICAO`, não como linha faltando.

      `confere`       quem está declarado como NÃO juntável tem de sair IMÓVEL no piso 0, e quem
                      está declarado juntável tem de se MEXER. É o que pega declaração errada:
                      nenhuma checagem de nome alcançaria uma linha que diz "não dá para juntar"
                      sobre uma premissa cujo número muda.

    ⚠️ IMÓVEL É NO PISO 0, e só. Nos pisos maiores até as premissas de tabela mudam, porque o
    `min_jogos` segue a célula — é a seção *Consequences* da ADR 0008, e cobrar igualdade nos
    demais pisos acusaria de defeito o comportamento que a ADR promete.

    ────────────────────────────────────────────────────────────────────────────────
    ⚠️ A QUEBRA POR FAMÍLIA É DEGENERADA NESTA JANELA, E ISSO É CONTEÚDO, NÃO FALHA. A janela
    congelada (16/06 a 04/08) pega o meio da virada de temporada europeia: as ligas split-year
    ainda não tinham começado e a Champions só aparece em 04/08 à noite, depois do teto. O
    resultado é um universo 100% ano-calendário. A coluna sai assim mesmo, com o número ao lado,
    porque `sem amostra` e `efeito nulo` são coisas diferentes e a segunda seria uma conclusão
    falsa sobre as europeias. A regra é a mesma da analyses/taskf_familia_e_mecanismo.sql.

    O universo da família sai do task01_base() sobre a camada MATERIALIZADA agora — que é a
    última célula que rodou —, enquanto o resto da tabela sai do carimbo. Por isso a coluna
    `confere_universo` compara os dois: se a materialização atual não for do mesmo lote que
    produziu a medição, o número de jogos denuncia.

    COMO RODAR (do dbt_futebol/):

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_entregavel
      bq query --use_legacy_sql=false --project_id=smartbetting-dados --max_rows=200 \
        < target/compiled/dbt_futebol/analyses/taskf_entregavel.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento. O
    `--max_rows` fica explícito por margem, não por necessidade de hoje: são 39 linhas mais 21 de
    anexo, abaixo do corte silencioso de 100 — mas o anexo cresce a cada benchmark novo, e o corte
    não avisa quando morde.)

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

,declaracao AS (
    SELECT * FROM UNNEST([
        STRUCT<mercado STRING, premissa STRING, fonte STRING, predicado STRING,
               escopo_hoje STRING, juntavel STRING, impedimento STRING, ressalva STRING>
        ('1X2', 'forca_mismatch',
         'int_futebol_team_form_pit · gols pró/contra por venue', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('1X2', 'superioridade_xg',
         'int_futebol_premissas_1x2 · spine de xG sobre fact_fixture_stats', 'premissas_1x2.spine',
         'competicao_e_temporada', 'sim',
         '',
         'xG não é coletado em toda competição; juntar o escopo não cria a cobertura que falta'),
        ('1X2', 'mando',
         'int_futebol_team_form_pit · aproveitamento em casa e fora', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('1X2', 'desfalque_adversario',
         'int_futebol_desfalques · boletim do próprio jogo', 'nenhum',
         'sem_historico', 'nao_se_aplica',
         '',
         'conta desfalque importante no jogo avaliado; não lê passado nenhum'),
        ('1X2', 'superioridade_tabela',
         'int_futebol_team_form_pit · CTE `tabela` (rank e ppg)', 'nenhum',
         'competicao_e_temporada', 'nao',
         'classificação só existe dentro de uma competição: não há rank num histórico juntado (ADR 0008)',
         'a alternativa séria — eleger uma competição principal por time — muda a definição da premissa e ficou para a [B]'),
        ('1X2', 'forma',
         'int_futebol_team_form_pit · vitórias nos 5 jogos anteriores', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('1X2', 'h2h_favoravel',
         'fact_h2h · confronto direto', 'nenhum',
         'cruza_tudo', 'ja_junto',
         '',
         'o join é por par de times e kickoff anterior, sem competição nem season — é a única fonte imune ao efeito medido'),
        ('Handicap', 'supremacia',
         'int_futebol_team_form_pit · CTE `tabela` (rank e ppg)', 'nenhum',
         'competicao_e_temporada', 'nao',
         'classificação só existe dentro de uma competição: não há rank num histórico juntado (ADR 0008)',
         ''),
        ('Handicap', 'tende_golear',
         'int_futebol_team_form_pit · gols pró/contra por venue', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Handicap', 'adversario_fragil_fora',
         'int_futebol_team_form_pit · gols sofridos do adversário por venue', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Handicap', 'mando_forte',
         'int_futebol_team_form_pit · aproveitamento em casa', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Handicap', 'sem_rodizio',
         'int_futebol_team_form_pit · CTE `tabela` (rank) e tamanho da liga', 'nenhum',
         'competicao_e_temporada', 'nao',
         'compara o rank contra o número de times da liga — nem o rank nem o `n_teams` existem num histórico juntado (ADR 0008)',
         'é a mais rígida das quatro de tabela: só acende em liga de pontos corridos, e por isso não se mexe em nenhum piso'),
        ('Handicap', 'raramente_perde_por_2',
         'int_futebol_premissas_ah · `margin_stats` sobre resultados anteriores', 'premissas_ah.margin',
         'competicao', 'sim',
         '',
         'o `margin_stats` não filtra season nem hoje: já atravessa temporada, então aqui o eixo de recorte ENCOLHE o histórico em vez de alargá-lo'),
        ('Handicap', 'defesa_fora_solida',
         'int_futebol_team_form_pit · gols sofridos por venue', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Handicap', 'favorito_irregular',
         'int_futebol_premissas_ah · `margin_stats` sobre resultados anteriores', 'premissas_ah.margin',
         'competicao', 'sim',
         '',
         'mesma do `raramente_perde_por_2`: a fonte já atravessa temporada, e sob recorte ela encolhe'),
        ('BTTS', 'ambos_marcam',
         'int_futebol_team_form_pit · failed-to-score% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('BTTS', 'ataque_dos_dois',
         'int_futebol_team_form_pit · gols feitos por venue', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('BTTS', 'defesas_vazaveis',
         'int_futebol_team_form_pit · clean sheet% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         'homônima da do Gols, com insumo e veredito próprios — as duas linhas não são a mesma premissa'),
        ('BTTS', 'historico_btts',
         'int_futebol_premissas_btts · últimos 5 jogos com os dois marcando', 'premissas_btts.last5',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('BTTS', 'defesa_forte',
         'int_futebol_team_form_pit · clean sheet% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('BTTS', 'ataque_trava',
         'int_futebol_team_form_pit · failed-to-score% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('BTTS', 'historico_seco',
         'int_futebol_premissas_btts · últimos 5 jogos sem os dois marcarem', 'premissas_btts.last5',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Dupla Chance', 'lado_coberto_forte',
         'int_futebol_premissas_1x2 · reuso de forca_mismatch OU superioridade_tabela', 'team_form_pit',
         'misto', 'sim',
         '',
         'metade juntável: `forca_mismatch` segue o eixo, `superioridade_tabela` não (ADR 0008) — e o OR basta para a premissa se mexer'),
        ('Dupla Chance', 'equilibrio_defensivo',
         'int_futebol_team_form_pit · gols sofridos + `team_hist` do DC (goleadas)', 'premissas_dc.hist',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Dupla Chance', 'adversario_limitado',
         'int_futebol_team_form_pit · aproveitamento do adversário OU h2h reusado do 1X2', 'team_form_pit',
         'misto', 'sim',
         '',
         'reusa a única fonte imune (h2h) e ainda assim se mexe: imunidade só se herda quando TODOS os insumos são imunes'),
        ('Dupla Chance', 'invicto_recente',
         'int_futebol_premissas_dc · `team_hist` (derrotas nos últimos 5)', 'premissas_dc.hist',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'ataque_combinado',
         'int_futebol_team_form_pit · gols feitos por venue dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'defesas_vazaveis',
         'int_futebol_team_form_pit · gols sofridos por venue dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         'homônima da do BTTS, com insumo e veredito próprios — as duas linhas não são a mesma premissa'),
        ('Gols', 'xg_combinado_alto',
         'int_futebol_premissas_ou · spine de xG sobre fact_fixture_stats', 'premissas_ou.spine',
         'competicao_e_temporada', 'sim',
         '',
         'xG não é coletado em toda competição; juntar o escopo não cria a cobertura que falta'),
        ('Gols', 'ritmo_alto',
         'int_futebol_premissas_ou · ritmo dos dois times contra a mediana da liga', 'premissas_ou.pool',
         'competicao_e_temporada', 'sim',
         '',
         'o POOL de times da mediana segue a competição do jogo em qualquer célula (é o benchmark "a liga em que estou jogando"); o que junta é o histórico de cada time do pool'),
        ('Gols', 'ambos_vazam',
         'int_futebol_team_form_pit · clean sheet% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'historico_over',
         'int_futebol_premissas_ou · total de gols dos últimos 5 jogos', 'premissas_ou.last5',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'defesas_firmes',
         'int_futebol_team_form_pit · gols sofridos por venue dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'clean_sheets_altos',
         'int_futebol_team_form_pit · clean sheet% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'xg_baixo_combinado',
         'int_futebol_premissas_ou · spine de xG sobre fact_fixture_stats', 'premissas_ou.spine',
         'competicao_e_temporada', 'sim',
         '',
         'xG não é coletado em toda competição; juntar o escopo não cria a cobertura que falta'),
        ('Gols', 'ataques_fracos',
         'int_futebol_team_form_pit · failed-to-score% dos dois times', 'team_form_pit',
         'competicao_e_temporada', 'sim',
         '',
         ''),
        ('Gols', 'historico_under',
         'int_futebol_premissas_ou · total de gols dos últimos 5 jogos', 'premissas_ou.last5',
         'competicao_e_temporada', 'sim',
         '',
         '')
    ])
),apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE (kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00'))
),

familia_do_universo AS (
    SELECT
        f.familia,
        COUNT(DISTINCT a.fixture_id) AS jogos
    FROM apostas_congeladas AS a
    JOIN familia_competicao AS f USING (competition)
    GROUP BY f.familia
),familia_resumo AS (
    SELECT
        COALESCE(SUM(IF(familia = 'ano_calendario', jogos, 0)), 0) AS jogos_ano_calendario,
        COALESCE(SUM(IF(familia = 'split_year',     jogos, 0)), 0) AS jogos_split_year,
        COALESCE(SUM(jogos), 0)                                    AS jogos_materializados
    FROM familia_do_universo
),hoje AS (
    SELECT * FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE celula = 'base' AND universo = 'completo'
),

junto AS (
    SELECT * FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE celula = 'escopo' AND universo = 'completo'
),lote AS (
    SELECT
        COUNT(DISTINCT git_sha)                       AS n_git_sha,
        COUNT(DISTINCT FORMAT('%t', odds_loaded_at))  AS n_odds_loaded_at,
        COUNT(DISTINCT CONCAT(celula, '|', universo)) AS n_grupos,
        MAX(git_sha)                                  AS git_sha,
        MAX(odds_loaded_at)                           AS odds_loaded_at
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
),medido AS (
    SELECT
        COALESCE(h.mercado, j.mercado)     AS mercado,
        COALESCE(h.premissa, j.premissa)   AS premissa,
        COALESCE(h.benchmark, j.benchmark) AS benchmark,
        COALESCE(h.usado_para_peso, j.usado_para_peso) AS usado_para_peso,
        h.celula IS NULL AS so_no_junto,
        j.celula IS NULL AS so_no_hoje,
        h.jogos_no_universo AS jogos_no_universo,
        h.janela_ini, h.janela_fim,
        h.medido_em AS medido_em_hoje, j.medido_em AS medido_em_junto,
        (IF(h.n_p0 IS DISTINCT FROM j.n_p0, 1, 0) + IF(h.a_odd_dava_p0 IS DISTINCT FROM j.a_odd_dava_p0, 1, 0) + IF(h.aconteceu_p0 IS DISTINCT FROM j.aconteceu_p0, 1, 0) + IF(h.diferenca_p0 IS DISTINCT FROM j.diferenca_p0, 1, 0))                    AS campos_piso0_mudados,
        h.n_p0  AS n_p0_hoje,  j.n_p0  AS n_p0_junto,
        h.n_p5  AS n_p5_hoje,  j.n_p5  AS n_p5_junto,
        h.diferenca_p0 AS dif_p0_hoje, j.diferenca_p0 AS dif_p0_junto,
        h.diferenca_p5 AS dif_p5_hoje, j.diferenca_p5 AS dif_p5_junto,
        h.peso_p5 AS peso_p5_hoje, j.peso_p5 AS peso_p5_junto,
        h.jogos_medios_disp AS jogos_hoje, j.jogos_medios_disp AS jogos_junto,
        h.pct_amostra_curta AS curta_hoje, j.pct_amostra_curta AS curta_junto
    FROM hoje AS h
    FULL OUTER JOIN junto AS j USING (mercado, premissa, benchmark)
),

juntado AS (
    SELECT
        COALESCE(m.mercado, d.mercado)   AS mercado,
        COALESCE(m.premissa, d.premissa) AS premissa,
        m.* EXCEPT (mercado, premissa),
        d.* EXCEPT (mercado, premissa),
        d.premissa IS NULL AS sem_declaracao,
        m.premissa IS NULL AS sem_medicao
    FROM medido AS m
    FULL OUTER JOIN declaracao AS d USING (mercado, premissa)
)

SELECT
    IF(COALESCE(j.usado_para_peso, TRUE), 'principal', 'anexo')  AS bloco,
    j.mercado,
    j.premissa,
    j.benchmark,
    j.usado_para_peso,

    -- COLUNA 1 do ticket: de onde puxa o histórico.
    j.fonte,
    j.predicado,
    -- COLUNA 2: se a janela é limitada à competição do jogo.
    j.escopo_hoje,
    -- COLUNA 3: se dá para juntar, e o que impede quando não dá.
    j.juntavel,
    j.impedimento,
    j.ressalva,

    -- COLUNA 4: o que o número vira. `hoje` = célula `base`; `junto` = célula `escopo`.
    j.n_p0_hoje,   j.n_p0_junto,
    j.dif_p0_hoje, j.dif_p0_junto,
    ROUND(j.dif_p0_junto - j.dif_p0_hoje, 1)      AS delta_dif_p0,
    j.n_p5_hoje,   j.n_p5_junto,
    j.dif_p5_hoje, j.dif_p5_junto,
    ROUND(j.dif_p5_junto - j.dif_p5_hoje, 1)      AS delta_dif_p5,
    j.peso_p5_hoje, j.peso_p5_junto,
    j.jogos_hoje,  j.jogos_junto,
    ROUND(j.jogos_junto - j.jogos_hoje, 1)        AS delta_jogos,
    j.curta_hoje,  j.curta_junto,
    ROUND(j.curta_junto - j.curta_hoje, 1)        AS delta_curta,

    -- COLUNA ADICIONAL: a quebra por família de competição. Ver o cabeçalho — nesta janela ela é
    -- degenerada, e o número ao lado é o que impede de ler isso como efeito nulo nas europeias.
    FORMAT('ano_calendario %d (%.1f%%) · split_year %d%s',
           fr.jogos_ano_calendario,
           SAFE_DIVIDE(fr.jogos_ano_calendario, fr.jogos_materializados) * 100,
           fr.jogos_split_year,
           IF(fr.jogos_split_year = 0, ' — SEM AMOSTRA', ''))                AS familia,
    fr.jogos_ano_calendario,
    fr.jogos_split_year,

    -- As duas conferências. Ver o cabeçalho.
    CASE
        WHEN j.sem_declaracao THEN 'SEM_DECLARACAO'
        WHEN j.sem_medicao    THEN 'SEM_MEDICAO'
        ELSE                       'CONFERE'
    END                                                                       AS cobertura,
    CASE
        WHEN j.so_no_hoje OR j.so_no_junto     THEN 'SEM_CONTRAPARTE'
        WHEN j.campos_piso0_mudados = 0        THEN 'IMOVEL_NO_PISO0'
        ELSE                                        'MUDOU'
    END                                                                       AS veredito_medicao,
    CASE
        WHEN j.sem_declaracao OR j.sem_medicao
          OR j.so_no_hoje OR j.so_no_junto     THEN 'NAO_COMPARAVEL'
        WHEN (j.juntavel = 'sim') = (j.campos_piso0_mudados > 0)
                                               THEN 'CONFERE'
        ELSE                                        'DIVERGE'
    END                                                                       AS confere,

    -- Carimbo. O lote é o da #58 e esta análise não o move; as colunas existem para que quem ler
    -- a tabela saiba de qual medição ela saiu sem ter de acreditar no doc.
    j.jogos_no_universo,
    fr.jogos_materializados,
    IF(j.jogos_no_universo = fr.jogos_materializados, 'CONFERE',
       FORMAT('DIVERGE (medido %d, materializado %d)',
              j.jogos_no_universo, fr.jogos_materializados))                  AS confere_universo,
    j.janela_ini,
    j.janela_fim,
    j.medido_em_hoje,
    j.medido_em_junto,
    l.git_sha,
    l.odds_loaded_at,
    IF(l.n_git_sha = 1 AND l.n_odds_loaded_at = 1,
       FORMAT('HOMOGENEO (%d grupos)', l.n_grupos),
       FORMAT('MISTURADO (%d shas, %d odds_loaded_at)', l.n_git_sha, l.n_odds_loaded_at))
                                                                              AS lote
FROM juntado AS j
CROSS JOIN familia_resumo AS fr
CROSS JOIN lote AS l
ORDER BY bloco, j.mercado, j.premissa, j.benchmark