{{ config(
    materialized='table',
    cluster_by=['competition', 'fixture_id'],
    description='O FUNIL DE AVALIAÇÃO (#95, ADR 0011 + ADR 0006). 1 linha por (fixture_id, market, outcome, line_value, janela) que TEVE PREÇO naquela janela, nos CINCO mercados pontuados (1X2, Handicap asiático, Gols O/U, Ambos Marcam, Dupla Chance) — e NADA filtrado. Cada porta do Motor é uma COLUNA BOOLEANA (TRUE = passou), nunca um WHERE: porta_saida_catalogada, porta_conjunto_completo, porta_valor_estimavel, porta_liquidez, porta_edge, porta_nota, porta_linha_meia, porta_odd_dc. `passou_no_gate` é a CONJUNÇÃO derivada das oito, jamais escrita à mão; `motivo_primario` é derivado por cima dos booleanos e é conveniência de leitura, não fonte (uma linha reprova em várias portas ao mesmo tempo, e é a leitura marginal — quantas linhas a porta ainda remove DEPOIS das anteriores — que dá valor à tabela). Cada porta é NULL-safe INDIVIDUALMENTE (COALESCE(..., FALSE)): insumo ausente reprova a porta em vez de propagar NULL para dentro da conjunção. UNIVERSO: os candidatos do int_futebol_odds_devig nos cinco mercados, quatro janelas (daily<t24h<t1h<t15m). Gols do 1º tempo (mercado 6) fica FORA — não existe modelo de premissa para ele e a sua ausência não é decisão nossa (ADR 0011). A saída "12" da Dupla Chance fica DENTRO, com porta_saida_catalogada=FALSE: ela é precificada e a decisão de não pontuá-la é nossa. As duas rejeições que hoje são SUMIÇO no fact_value_opportunities — conjunto de saídas incompleto (a maior do sistema) e a "12" da DC — passam a ser linha com carimbo: os WHERE de completude de cada ramo viram coluna e o INNER JOIN com as premissas vira LEFT JOIN. `janela_e_corrente` é COLUNA e fica FORA da conjunção: é redução (qual janela publica), não veredito de qualidade (ADR 0011, D8). O EXPURGO NÃO É PORTA (ADR 0011): o funil guarda jogo encerrado de propósito — é ele que responde quanto rendeu a faixa descartada — e o expurgo continua no board, sobre o status vindo de fact_fixtures. Por isso `kickoff_utc` sai daqui e o STATUS não: status muda depois do apito e uma coluna congelada com o status de antes mentiria (ADR 0011, D10). Sem evidencias[]/avisos[]: são derivados e reconstruíveis. O EMPATE DO 1X2 carrega marca própria (`sem_lado_apostado`): sem lado apostado nenhuma premissa dispara, e um terço do universo do 1X2 está em zero POR CONSTRUÇÃO — sob o motivo genérico ele seria lido como severidade da régua (ADR 0005/0006). MATERIALIZAÇÃO TABELA nesta entrega (#95): a tabela nasce cobrindo desde a primeira odd coletada (16/06), então o backfill sai de graça. O append-only com congelamento no apito (ADR 0011) é a próxima entrega. NÃO VAI PARA O SUPABASE: o app não lê funil — sem migração no Postgres, sem RPC, sem tocar check_schema_parity. O board NÃO muda nesta entrega; quem prova que o funil o descreve de verdade é a guarda assert_funil_paridade_com_board, e quem prova que o universo está inteiro é assert_funil_reconcilia_com_devig (que lê a FONTE, nunca o próprio funil).'
) }}

-- ============================================================================
-- O UNIVERSO SAI DO DE-VIG, NÃO DAS PREMISSAS — e essa é a inversão da entrega.
--
-- O `fact_value_opportunities` parte das premissas e faz `INNER JOIN` com o de-vig.
-- Sob essa direção a saída "12" da Dupla Chance (precificada, não pontuada) some antes
-- de qualquer porta, e o mesmo vale para toda saída sem modelo. Aqui o de-vig é o lado
-- de FORA: candidato é linha que teve preço (ADR 0006), e o que falta do lado das
-- premissas vira porta FALSE, não ausência.
--
-- A guarda `assert_funil_reconcilia_com_devig` amarra isso: linhas do funil = candidatos
-- do de-vig nos cinco mercados. Nenhum join abaixo pode acrescentar nem tirar linha.
-- ============================================================================
WITH devig AS (
    SELECT
        *,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM ({{ futebol_devig_todas_janelas() }})
    -- OS CINCO MERCADOS PONTUADOS. O 6 (Gols O/U do 1º tempo) é coletado e passa pelo
    -- de-vig, mas não tem modelo de premissa: gravá-lo como "rejeitado" registraria como
    -- decisão nossa a ausência de um modelo que nunca escrevemos (ADR 0011).
    WHERE market_id IN ({{ futebol_mercados_pontuados_ids() }})
),

-- A corroboração já vem reduzida à janela corrente e com grão (fixture, mercado, saída,
-- linha) — sem janela. O join abaixo, portanto, é o MESMO do board: a linha de t24h e a
-- de t15m recebem a mesma corroboração. Não é descuido do funil, é o grão do modelo a
-- montante, e mudá-lo aqui quebraria a paridade.
corro AS (
    SELECT
        *,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM {{ ref('int_futebol_corroboracao') }}
),

prem_1x2 AS (
    SELECT * FROM {{ ref('int_futebol_premissas_1x2') }}
),

prem_ou AS (
    SELECT * FROM {{ ref('int_futebol_premissas_ou') }}
),

prem_ah AS (
    SELECT * FROM {{ ref('int_futebol_premissas_ah') }}
),

prem_btts AS (
    SELECT * FROM {{ ref('int_futebol_premissas_btts') }}
),

prem_dc AS (
    SELECT * FROM {{ ref('int_futebol_premissas_dc') }}
),

-- SÓ O KICKOFF, e o status DE PROPÓSITO fora (ADR 0011, D10). O kickoff é o que o
-- congelamento da próxima entrega vai usar e o que toda análise por horizonte precisa;
-- o status muda DEPOIS do apito, e uma linha congelada carregando o status de antes
-- mentiria. Quem quiser status junta `fact_fixtures` — que é onde ele está certo.
fixtures AS (
    SELECT
        fixture_id,
        kickoff_utc AS _fx_kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

-- ============================================================================
-- Ramo 1X2 (market_id=1). Saídas catalogadas: Home / Draw / Away.
-- Completude do conjunto = 1X2 inteiro na Pinnacle (pin_n_outcomes >= 3) — o MESMO
-- predicado que hoje é `WHERE d.pin_n_outcomes >= 3` no ramo do board, virado coluna.
-- ============================================================================
cand_1x2 AS (
    SELECT
        d.fixture_id,
        '{{ futebol_mercados_pontuados()[1] }}'         AS market,
        d.outcome_side                                  AS outcome,
        CAST(NULL AS FLOAT64)                           AS line_value,
        d.competition,
        d.season,
        d.janela_usada,
        d.janela_prioridade,
        d.janela_e_corrente,

        d.edge,
        COALESCE(d.pts_valor, 0)                        AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.n_outcomes_valor,
        d.valor_fonte,
        COALESCE(d.penalidades_globais_pts, 0)          AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.premissas_sem_dado,
        p.penalidades_1x2_pts                           AS penalidades_especificas_pts,

        COALESCE(c.pts_corroboracao, 0)                 AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)          AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE)         AS linha_sharp_confirma,

        COALESCE(d.outcome_side IN ('Home', 'Draw', 'Away'), FALSE) AS porta_saida_catalogada,
        COALESCE(d.pin_n_outcomes >= 3, FALSE)          AS porta_conjunto_completo,
        -- O EMPATE (ADR 0005/0006). Não tem lado apostado: nenhuma premissa do 1X2 se
        -- aplica, o teto de premissa é zero e — quando a A6 introduzir o denominador —
        -- ele também será zero, explicitamente antes da divisão. A marca é ESTRUTURAL
        -- (o mercado e a saída), nunca "a nota deu zero": é ela que impede que um terço
        -- do universo do 1X2, que está em zero por construção, seja lido como
        -- severidade da régua.
        COALESCE(d.outcome_side = 'Draw', FALSE)        AS sem_lado_apostado
    FROM devig d
    LEFT JOIN prem_1x2 p
        ON  p.fixture_id = d.fixture_id
       AND  p.outcome    = d.outcome_side
    LEFT JOIN corro c
        ON  c.market_id    = d.market_id
       AND  c.fixture_id   = d.fixture_id
       AND  c.outcome_side = d.outcome_side
    WHERE d.market_id = 1
),

-- ============================================================================
-- Ramo Gols O/U (market_id=5). Saídas catalogadas: Over / Under.
-- Completude = par Over+Under da Pinnacle na linha (pin_n_outcomes >= 2).
-- ============================================================================
cand_ou AS (
    SELECT
        d.fixture_id,
        '{{ futebol_mercados_pontuados()[5] }}'         AS market,
        d.outcome_side                                  AS outcome,
        d.line_value,
        d.competition,
        d.season,
        d.janela_usada,
        d.janela_prioridade,
        d.janela_e_corrente,

        d.edge,
        COALESCE(d.pts_valor, 0)                        AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.n_outcomes_valor,
        d.valor_fonte,
        COALESCE(d.penalidades_globais_pts, 0)          AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.premissas_sem_dado,
        p.penalidades_ou_pts                            AS penalidades_especificas_pts,

        COALESCE(c.pts_corroboracao, 0)                 AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)          AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE)         AS linha_sharp_confirma,

        COALESCE(d.outcome_side IN ('Over', 'Under'), FALSE) AS porta_saida_catalogada,
        COALESCE(d.pin_n_outcomes >= 2, FALSE)          AS porta_conjunto_completo,
        FALSE                                           AS sem_lado_apostado
    FROM devig d
    LEFT JOIN prem_ou p
        ON  p.fixture_id = d.fixture_id
       AND  p.outcome    = d.outcome_side
       AND  COALESCE(CAST(p.line_value AS STRING), 'NONE') = d.line_key
    LEFT JOIN corro c
        ON  c.market_id    = d.market_id
       AND  c.fixture_id   = d.fixture_id
       AND  c.outcome_side = d.outcome_side
       AND  c.line_key     = d.line_key
    WHERE d.market_id = 5
),

-- ============================================================================
-- Ramo Handicap asiático (market_id=4). Saídas catalogadas: Home / Away.
-- `line_value` é o handicap na ótica do MANDANTE e é o MESMO para Home e Away (par
-- complementar). Completude = par da Pinnacle (pin_n_outcomes >= 2).
-- ============================================================================
cand_ah AS (
    SELECT
        d.fixture_id,
        '{{ futebol_mercados_pontuados()[4] }}'         AS market,
        d.outcome_side                                  AS outcome,
        d.line_value,
        d.competition,
        d.season,
        d.janela_usada,
        d.janela_prioridade,
        d.janela_e_corrente,

        d.edge,
        COALESCE(d.pts_valor, 0)                        AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.n_outcomes_valor,
        d.valor_fonte,
        COALESCE(d.penalidades_globais_pts, 0)          AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.premissas_sem_dado,
        p.penalidades_ah_pts                            AS penalidades_especificas_pts,

        COALESCE(c.pts_corroboracao, 0)                 AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)          AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE)         AS linha_sharp_confirma,

        COALESCE(d.outcome_side IN ('Home', 'Away'), FALSE) AS porta_saida_catalogada,
        COALESCE(d.pin_n_outcomes >= 2, FALSE)          AS porta_conjunto_completo,
        FALSE                                           AS sem_lado_apostado
    FROM devig d
    LEFT JOIN prem_ah p
        ON  p.fixture_id = d.fixture_id
       AND  p.outcome    = d.outcome_side
       AND  COALESCE(CAST(p.line_value AS STRING), 'NONE') = d.line_key
    LEFT JOIN corro c
        ON  c.market_id    = d.market_id
       AND  c.fixture_id   = d.fixture_id
       AND  c.outcome_side = d.outcome_side
       AND  c.line_key     = d.line_key
    WHERE d.market_id = 4
),

-- ============================================================================
-- Ramo Ambos Marcam / BTTS (market_id=8). Saídas catalogadas: Yes / No.
-- A Pinnacle NÃO precifica BTTS -> o valor vem do CONSENSO, e a completude é medida
-- por `n_outcomes_valor >= 2` (o par Yes+No da mediana), não por pin_n_outcomes —
-- que fica NULL aqui, honestamente.
-- ============================================================================
cand_btts AS (
    SELECT
        d.fixture_id,
        '{{ futebol_mercados_pontuados()[8] }}'         AS market,
        d.outcome_side                                  AS outcome,
        CAST(NULL AS FLOAT64)                           AS line_value,
        d.competition,
        d.season,
        d.janela_usada,
        d.janela_prioridade,
        d.janela_e_corrente,

        d.edge,
        COALESCE(d.pts_valor, 0)                        AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.n_outcomes_valor,
        d.valor_fonte,
        COALESCE(d.penalidades_globais_pts, 0)          AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        d.pen_odd_juice,

        p.pts_premissas,
        p.premissas_sem_dado,
        p.penalidades_btts_pts                          AS penalidades_especificas_pts,

        COALESCE(c.pts_corroboracao, 0)                 AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)          AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE)         AS linha_sharp_confirma,

        COALESCE(d.outcome_side IN ('Yes', 'No'), FALSE) AS porta_saida_catalogada,
        COALESCE(d.n_outcomes_valor >= 2, FALSE)        AS porta_conjunto_completo,
        FALSE                                           AS sem_lado_apostado
    FROM devig d
    LEFT JOIN prem_btts p
        ON  p.fixture_id = d.fixture_id
       AND  p.outcome    = d.outcome_side
    LEFT JOIN corro c
        ON  c.market_id    = d.market_id
       AND  c.fixture_id   = d.fixture_id
       AND  c.outcome_side = d.outcome_side
    WHERE d.market_id = 8
),

-- ============================================================================
-- Ramo Dupla Chance (market_id=12). Saídas catalogadas: 1X / X2 — a "12" NÃO.
--
-- É AQUI que a segunda rejeição invisível vira linha. A DC é cotada em três saídas e o
-- Motor pontua duas; o `INNER JOIN` com as premissas engolia a "12" (1.059 linhas, um
-- terço exato do universo de DC, na foto de 19/08) antes de qualquer porta. Com o LEFT
-- JOIN ela entra com `porta_saida_catalogada = FALSE`, que é o que ela é: uma decisão
-- nossa de não pontuar, não uma ausência de mercado.
--
-- Completude = conjunto 1X2 DE ORIGEM completo (n_outcomes_valor >= 3): a prob justa da
-- DC é derivada do de-vig 1X2 da Pinnacle. E a DC tem GATE DE ODD PRÓPRIO
-- (best_odd >= 1,25), que hoje mora no `WHERE` do ramo do board e aqui é a
-- `porta_odd_dc`.
-- ============================================================================
cand_dc AS (
    SELECT
        d.fixture_id,
        '{{ futebol_mercados_pontuados()[12] }}'        AS market,
        d.outcome_side                                  AS outcome,
        CAST(NULL AS FLOAT64)                           AS line_value,
        d.competition,
        d.season,
        d.janela_usada,
        d.janela_prioridade,
        d.janela_e_corrente,

        d.edge,
        COALESCE(d.pts_valor, 0)                        AS pts_valor,
        d.best_odd,
        d.best_book,
        d.avg_odd,
        d.n_casas,
        d.prob_justa_fechamento,
        d.pin_n_outcomes,
        d.n_outcomes_valor,
        d.valor_fonte,
        -- penalidades globais SEM o juice: o gate de odd próprio da DC (>= 1,25) já
        -- garante o retorno mínimo. Idêntico ao ramo `joined_dc` do board — a paridade
        -- exige a nota byte a byte, e o juice vale −10 pontos.
        ( 30 * CAST(d.pen_odd_outlier  AS INT64)
        + 12 * CAST(d.pen_poucas_casas AS INT64)
        + 15 * CAST(d.pen_odd_longshot AS INT64) )      AS penalidades_globais_pts,
        d.pen_odd_outlier,
        d.pen_poucas_casas,
        d.pen_odd_longshot,
        FALSE                                           AS pen_odd_juice,

        p.pts_premissas,
        p.premissas_sem_dado,
        -- A DC não tem penalidade específica (o gate de odd próprio já barra o retorno
        -- baixo). É constante no board e é constante aqui — inclusive na "12", onde não
        -- há premissa nenhuma para o LEFT JOIN trazer.
        CAST(0 AS INT64)                                AS penalidades_especificas_pts,

        COALESCE(c.pts_corroboracao, 0)                 AS pts_corroboracao,
        COALESCE(c.modelo_api_concorda, FALSE)          AS modelo_api_concorda,
        COALESCE(c.linha_sharp_confirma, FALSE)         AS linha_sharp_confirma,

        COALESCE(d.outcome_side IN ('1X', 'X2'), FALSE) AS porta_saida_catalogada,
        COALESCE(d.n_outcomes_valor >= 3, FALSE)        AS porta_conjunto_completo,
        FALSE                                           AS sem_lado_apostado
    FROM devig d
    LEFT JOIN prem_dc p
        ON  p.fixture_id = d.fixture_id
       AND  p.outcome    = d.outcome_side
    LEFT JOIN corro c
        ON  c.market_id    = d.market_id
       AND  c.fixture_id   = d.fixture_id
       AND  c.outcome_side = d.outcome_side
    WHERE d.market_id = 12
),

unioned AS (
    SELECT * FROM cand_1x2
    UNION ALL
    SELECT * FROM cand_ou
    UNION ALL
    SELECT * FROM cand_ah
    UNION ALL
    SELECT * FROM cand_btts
    UNION ALL
    SELECT * FROM cand_dc
),

-- ============================================================================
-- A NOTA, na mesma aritmética do board — de propósito, e essa é a decisão de risco
-- desta entrega: a fórmula existe em dois lugares até o flip (passo 2), e é a guarda
-- de paridade que impede as duas cópias de divergirem em silêncio.
--
-- `pts_premissas` e `penalidades_especificas_pts` NÃO levam COALESCE. Saída sem
-- premissa (a "12" da DC) resolve a nota para NULL, e o NULL morre na `porta_nota`,
-- que é NULL-safe. Somar zero no lugar diria que a linha foi avaliada e tirou zero —
-- que é diferente de não ter sido avaliada, e é a distinção que a ADR 0003 preserva.
--
-- ⚠️ Isto NÃO contraria a regra do CODING_STANDARDS.md ("missing data must resolve to
-- FALSE, never a NULL propagated into the Score"). Aquela regra é sobre INSUMO de
-- premissa — degradação graciosa: dado ausente não acende a premissa, e é ela que
-- resolve para FALSE. Aqui não falta insumo: falta a AVALIAÇÃO inteira, porque a saída
-- não é catalogada. E o NULL não se propaga para dentro de veredito nenhum — todas as
-- oito portas o absorvem individualmente, que é o que a regra existe para garantir.
-- No board esta linha nem existia; só aqui ela precisa de um valor, e nenhum número
-- seria honesto.
-- ============================================================================
scored AS (
    SELECT
        *,
        (penalidades_globais_pts + penalidades_especificas_pts) AS penalidades,
        LEAST(GREATEST(
            pts_valor + pts_premissas + pts_corroboracao
            - (penalidades_globais_pts + penalidades_especificas_pts), 0), 100) AS score,
        -- linha "meia" (.5) é a única SEM push/meio-push. NULL onde não há linha.
        (MOD(CAST(ROUND(ABS(line_value) * 2) AS INT64), 2) = 1) AS is_half_line
    FROM unioned
),

-- ============================================================================
-- AS OITO PORTAS. TRUE = passou. Cada uma é NULL-safe SOZINHA — insumo ausente
-- reprova a porta em vez de propagar NULL para dentro da conjunção. É a degradação
-- graciosa do Motor, e é o que impede o descarte silencioso que a ADR 0006 proíbe.
--
-- ⚠️ `porta_conjunto_completo` e `porta_valor_estimavel` são ANINHADAS: pela ADR 0002,
-- conjunto incompleto implica prob justa ausente. As duas ficam mesmo assim, porque a
-- leitura marginal é o produto da tabela — mas quem somar as duas como se fossem
-- independentes conta a mesma linha duas vezes.
-- ============================================================================
com_portas AS (
    SELECT
        *,
        (prob_justa_fechamento IS NOT NULL)                 AS porta_valor_estimavel,
        COALESCE(n_casas >= 3, FALSE)                       AS porta_liquidez,
        COALESCE(
            edge > CASE
                     -- edge de CONSENSO (o BTTS, que a Pinnacle não precifica) é
                     -- enviesado p/ cima — best_odd é o MÁXIMO das casas contra a prob
                     -- da MEDIANA — e por isso exige piso maior.
                     WHEN valor_fonte = 'consenso' THEN {{ var('consensus_min_edge', 0.03) }}
                     ELSE 0
                   END,
            FALSE)                                          AS porta_edge,
        COALESCE(score >= 40, FALSE)                        AS porta_nota,
        -- Handicap e Gols exigem linha meia (.5): nas outras o resultado pode dar
        -- push/meio-push e o de-vig 2-way superdimensiona o edge. Mercado sem linha
        -- passa trivialmente — não é isenção, é que a porta não se aplica.
        COALESCE(
            market NOT IN ('{{ futebol_mercados_pontuados()[4] }}',
                           '{{ futebol_mercados_pontuados()[5] }}') OR is_half_line,
            FALSE)                                          AS porta_linha_meia,
        -- Gate de odd próprio da Dupla Chance. Trivialmente TRUE nos outros quatro.
        COALESCE(
            market <> '{{ futebol_mercados_pontuados()[12] }}' OR best_odd >= 1.25,
            FALSE)                                          AS porta_odd_dc
    FROM scored
),

-- ============================================================================
-- A CONJUNÇÃO, e só ela. `passou_no_gate` é DERIVADO das oito colunas acima — nunca
-- escrito à mão, nunca uma segunda cópia do gate do board. Se uma porta nova entrar,
-- ela entra aqui e a conjunção a absorve.
--
-- `janela_e_corrente` NÃO está na conjunção (ADR 0011, D8): ela responde "qual janela
-- publica", que é redução, não veredito de qualidade. Somá-la ao gate sujaria a
-- aritmética do funil — toda taxa de rejeição passaria a incluir três janelas que
-- ninguém rejeitou.
--
-- O EXPURGO também não está (ADR 0011): o funil guarda jogo encerrado de propósito.
-- Quem filtra por status é o board.
-- ============================================================================
com_gate AS (
    SELECT
        *,
        (   porta_saida_catalogada
        AND porta_conjunto_completo
        AND porta_valor_estimavel
        AND porta_liquidez
        AND porta_edge
        AND porta_nota
        AND porta_linha_meia
        AND porta_odd_dc ) AS passou_no_gate
    FROM com_portas
)

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    janela_usada                AS janela,
    janela_prioridade,
    -- redução, não veredito: diz qual das quatro janelas o board publicaria. Quem for
    -- contar o funil precisa FIXAR uma janela por candidato antes de contar — contando
    -- as quatro, todo número infla até 4×.
    janela_e_corrente,

    competition,
    season,
    -- o kickoff é o eixo de todo horizonte, e é o que a próxima entrega usa para
    -- congelar a linha no apito.
    _fx_kickoff_utc             AS kickoff_utc,

    -- ---------------------------------------------------------------- as oito portas
    porta_saida_catalogada,
    porta_conjunto_completo,
    porta_valor_estimavel,
    porta_liquidez,
    porta_edge,
    porta_nota,
    porta_linha_meia,
    porta_odd_dc,
    passou_no_gate,

    -- CONVENIÊNCIA DE LEITURA, NÃO FONTE (ADR 0006). Uma linha reprova em várias portas
    -- ao mesmo tempo, e um campo único de motivo é vitória do primeiro da fila: ele
    -- destrói exatamente a distinção que dá valor à tabela — quantas linhas a porta
    -- remove SOZINHA contra quantas ela ainda remove DEPOIS das anteriores. Quem for
    -- medir porta lê os booleanos; isto aqui serve para olhar uma linha e entender.
    --
    -- A ordem é a de leitura declarada na ADR 0011 (D5), e o empate tem lugar próprio
    -- dentro da porta de nota: sem ele, um terço do universo do 1X2 apareceria como
    -- "nota abaixo da régua" e a régua pareceria mais severa no 1X2 do que é.
    CASE
        WHEN NOT porta_saida_catalogada  THEN 'saida_nao_catalogada'
        WHEN NOT porta_conjunto_completo THEN 'conjunto_incompleto'
        WHEN NOT porta_valor_estimavel   THEN 'valor_nao_estimavel'
        WHEN NOT porta_liquidez          THEN 'sem_liquidez'
        WHEN NOT porta_edge              THEN 'sem_edge'
        WHEN NOT porta_nota
            THEN IF(sem_lado_apostado, 'sem_lado_apostado', 'nota_abaixo_da_regua')
        WHEN NOT porta_linha_meia        THEN 'linha_nao_meia'
        WHEN NOT porta_odd_dc            THEN 'odd_dc_abaixo_do_minimo'
        ELSE NULL
    END AS motivo_primario,

    -- O empate do 1X2 — marca ESTRUTURAL, e não "a nota deu zero" (ADR 0005/0006).
    sem_lado_apostado,

    -- ------------------------------------------------------- componentes numéricos
    edge,
    pts_valor,
    -- NULL onde não houve premissa a avaliar (a "12" da DC). Zero seria "foi avaliada e
    -- tirou zero", que é outra coisa — ADR 0003.
    pts_premissas,
    pts_corroboracao,
    penalidades_globais_pts,
    penalidades_especificas_pts,
    penalidades,
    score,
    -- quantas premissas aplicáveis à linha não puderam ser avaliadas por falta de
    -- insumo (#41). Não entra na nota: é o que a nota NÃO pôde levar em conta.
    premissas_sem_dado,

    -- as quatro parcelas da penalidade global (#87). Na DC o juice é FALSE de propósito.
    pen_odd_outlier,
    pen_poucas_casas,
    pen_odd_longshot,
    pen_odd_juice,
    -- as duas parcelas da corroboração — mesma lição da #87: parcela publicada é
    -- parcela lida, em vez de readivinhada por uma chave que não desempata.
    modelo_api_concorda,
    linha_sharp_confirma,

    -- ------------------------------------------------------------ contexto de odds
    best_odd,
    best_book,
    avg_odd,
    n_casas,
    prob_justa_fechamento,
    valor_fonte,
    pin_n_outcomes,
    n_outcomes_valor,
    is_half_line,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM com_gate
-- LEFT, nunca INNER: fixture ausente em `fact_fixtures` não pode sumir do funil — sumir
-- seria a perda silenciosa que a tabela inteira existe para impedir, e quebraria a
-- reconciliação contra o de-vig. O kickoff vem NULL e diz isso de si mesmo.
LEFT JOIN fixtures USING (fixture_id)
