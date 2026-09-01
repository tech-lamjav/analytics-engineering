{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['fixture_id', 'market', 'outcome', 'line_key', 'janela'],
    on_schema_change='append_new_columns',
    full_refresh=false,
    cluster_by=['competition', 'fixture_id'],
    description='⚠️ A VIRADA (#109), 2026-09-01: a conjunção de `passou_no_gate` trocou de gate de PREÇO para gate de QUALIDADE DE DADO — porta_edge e porta_nota saíram, porta_liquidez_estrita/porta_outlier/porta_faixa_odd entraram no lugar de porta_liquidez. O texto abaixo, escrito antes da virada, ainda descreve as três barreiras como "medidas e fora da conjunção" e o board como "sem mudar" — está desatualizado nesses pontos; o board muda de volume e composição a partir deste commit, sob coordenação com a prop-play-predictor#301/#309. O FUNIL DE AVALIAÇÃO (#95/#96, ADR 0011 + ADR 0006). 1 linha por (fixture_id, market, outcome, line_value, janela) que TEVE PREÇO naquela janela, nos CINCO mercados pontuados (1X2, Handicap asiático, Gols O/U, Ambos Marcam, Dupla Chance) — e NADA filtrado. Cada porta do Motor é uma COLUNA BOOLEANA (TRUE = passou), nunca um WHERE: porta_saida_catalogada, porta_cobertura_pinnacle, porta_valor_estimavel, porta_liquidez, porta_edge, porta_nota, porta_linha_meia, porta_odd_dc. `passou_no_gate` é a CONJUNÇÃO derivada das oito, jamais escrita à mão; `motivo_primario` é derivado por cima dos booleanos e é conveniência de leitura, não fonte (uma linha reprova em várias portas ao mesmo tempo, e é a leitura marginal — quantas linhas a porta ainda remove DEPOIS das anteriores — que dá valor à tabela). Cada porta é NULL-safe INDIVIDUALMENTE (COALESCE(..., FALSE)): insumo ausente reprova a porta em vez de propagar NULL para dentro da conjunção. UNIVERSO: os candidatos do int_futebol_odds_devig nos cinco mercados, quatro janelas (daily<t24h<t1h<t15m). Gols do 1º tempo (mercado 6) fica FORA — não existe modelo de premissa para ele e a sua ausência não é decisão nossa (ADR 0011). A saída "12" da Dupla Chance fica DENTRO, com porta_saida_catalogada=FALSE: ela é precificada e a decisão de não pontuá-la é nossa. As duas rejeições que hoje são SUMIÇO no fact_value_opportunities — conjunto de saídas incompleto (a maior do sistema) e a "12" da DC — passam a ser linha com carimbo: os WHERE de completude de cada ramo viram coluna e o INNER JOIN com as premissas vira LEFT JOIN. `janela_e_corrente` é COLUNA e fica FORA da conjunção: é redução (qual janela publica), não veredito de qualidade (ADR 0011, D8). O EXPURGO NÃO É PORTA (ADR 0011): o funil guarda jogo encerrado de propósito — é ele que responde quanto rendeu a faixa descartada — e o expurgo continua no board, sobre o status vindo de fact_fixtures. Por isso `kickoff_utc` sai daqui e o STATUS não: status muda depois do apito e uma coluna congelada com o status de antes mentiria (ADR 0011, D10). Sem evidencias[]/avisos[]: são derivados e reconstruíveis. O EMPATE DO 1X2 carrega marca própria (`sem_lado_apostado`): sem lado apostado nenhuma premissa dispara, e um terço do universo do 1X2 está em zero POR CONSTRUÇÃO — sob o motivo genérico ele seria lido como severidade da régua (ADR 0005/0006). APPEND-ONLY, CONGELADO NO APITO (#96, ADR 0011): materialização INCREMENTAL por merge no grão (fixture_id, market, outcome, line_key, janela). A linha é escrita e atualizada enquanto o kickoff do fixture está no FUTURO e nenhuma escrita acontece depois dele — o funil deixa de ser uma foto do que o código de hoje diria e passa a ser registro do que o Motor disse. `full_refresh=false` no config porque a fase de RECOVERY do workflow_futebol_odds roda o mesmo --select com --full-refresh: sem isso, a primeira recuperação de deriva apagaria o histórico inteiro. Toda linha carrega `gravado_em` e `origem`: `backfill` no build que cria a tabela (recalculado com o código de hoje, e é a única parte que NÃO é registro de época) e `corrente` em toda escrita incremental. Jogo adiado (PST/SUSP) cujo kickoff volta para o futuro VOLTA a ser gravável — o filtro lê o kickoff corrente, não o da escrita anterior. Fixture ausente em fact_fixtures (kickoff NULL) é FAIL-OPEN: continua gravável para sempre, porque perdê-lo quebraria a reconciliação (ADR 0003). NÃO HÁ EXPURGO DO FUNIL (~45 mil linhas/mês; a política se revisita se a tabela passar de 10 milhões de linhas). NÃO VAI PARA O SUPABASE: o app não lê funil — sem migração no Postgres, sem RPC, sem tocar check_schema_parity. O board NÃO muda nesta entrega; quem prova que o funil o descreve de verdade é a guarda assert_funil_paridade_com_board, e quem prova que o universo está inteiro é assert_funil_reconcilia_com_devig (que lê a FONTE, nunca o próprio funil). A NOTA DE CONTEXTO (#103, ADR 0012): a coluna `nota_contexto` é a nota depois que o preço sai dela — pts_premissas menos as penalidades de CONTEXTO (pick_empate −10, desfalque_proprio −15, linha_extrema −10, handicap_alto −12), com GREATEST(..., 0) —, e nada mais: sem pts_valor, sem corroboração e sem as quatro penalidades de odd. Ela nasce AO LADO do `score`, que continua sendo o do board: nesta entrega o produto não muda de gate nem de número, e existe UMA virada só, no fim da [A]. A composição mora em macros/futebol_nota_contexto.sql (num lugar só, consumida pelo funil e pela guarda de reconstrução, nunca copiada); duas guardas a protegem — assert_nota_contexto_sem_preco (sentinela da decisão: falha se qualquer componente de preço aparecer no texto da composição) e assert_funil_nota_contexto_reconstroi (a coluna gravada bate com a recomposta). NULL onde não houve premissa a avaliar (a "12" da DC), pelo mesmo motivo que o score (ADR 0003). ⚠️ A coluna chega por append_new_columns e SÓ nas linhas que o congelamento ainda deixa gravar: as linhas de jogo já apitado antes do deploy da A1 ficam com nota_contexto NULL para sempre, e isso é o append-only funcionando (ADR 0011), não defeito — a guarda de reconstrução é escopada a elas de propósito. A NOTA NORMALIZADA (#105, ADR 0005): as colunas `lado` e `score_normalizado`. `lado` é o eixo do denominador — os ONZE pares de (mercado, lado) que `futebol_lado()` enumera, e no Handicap ele NÃO é o outcome (é o sinal do handicap na ótica do lado apostado: Favorito/Azarao/Pick), enquanto na Dupla Chance 1X e X2 colapsam em `unico` porque as quatro premissas se aplicam às duas saídas. `score_normalizado` é a nota de contexto dividida pelo p95 OBSERVADO daquele lado, congelado no seed versionado `futebol_p95_nota_contexto` (medido uma vez, sobre janela declarada — recalcular em runtime faria a régua significar coisa diferente a cada dia). A nota é ABSOLUTA — quanta evidência acendeu —, nunca percentil dentro do lado: o preço declarado é que os mercados publicam em taxas diferentes, e isso é consequência, não defeito. Clamp em 100 EXPLÍCITO, porque com o p95 no denominador ~5% das linhas de cada lado ficam acima de 100 por construção. Denominador zero (o empate do 1X2 e o Pick do Handicap, que não têm lado apostado) resolve para ZERO explícito e nunca por SAFE_DIVIDE: o NULL faria a comparação com a régua virar NULL e a linha sairia sem passar e sem ser marcada. Denominador AUSENTE (lado fora do seed) cai no mesmo ramo — o join é LEFT para que a linha nunca suma — e quem acende é assert_p95_nota_contexto_nao_derivou, que cobra tanto a COBERTURA dos onze lados quanto a DERIVA do p95 vivo contra o congelado. A aritmética mora em macros/futebol_score_normalizado.sql, sem argumento, pela mesma razão do macro da nota de contexto. O BOARD NÃO MUDA: ele segue no `score` e no gate de 40, e a virada é uma só, no fim da [A]. ⚠️ As duas colunas chegam por append_new_columns e SÓ nas linhas que o congelamento ainda deixa gravar — linha de jogo já apitado antes do deploy fica com elas NULL para sempre, e isso é o append-only funcionando. AS TRÊS BARREIRAS DE PREÇO (#104, A3+A5): as colunas `porta_liquidez_estrita` (n_casas >= 4), `porta_outlier` (NOT pen_odd_outlier) e `porta_faixa_odd` (best_odd dentro de [1,50; 4,00], e [1,25; 2,00] na Dupla Chance, fronteiras INCLUSIVAS nas duas pontas). Elas são MEDIDAS e ficam FORA de `passou_no_gate` — dizem quem passaria sem remover ninguém; quem as põe em vigor é a virada (#109), que no mesmo ato tira a `porta_liquidez` (>= 3) e põe a `porta_liquidez_estrita` no lugar. ⚠️ A de liquidez tem NOME PRÓPRIO em vez de a `porta_liquidez` ser redefinida para 4, e isso é decisão: o funil é append-only, então redefinir o predicado no lugar faria um nome de coluna valer >= 3 nas linhas congeladas e >= 4 nas novas, para sempre, dentro do registro de época — e as outras duas saídas (mínimo 4 dentro da conjunção, ou a porta de liquidez fora dela) mudariam o board, contra o aceite. As duas convivem e a virada troca qual está na conjunção, sem renomear nada. `porta_outlier` inverte a polaridade da penalidade (penalidade TRUE = suspeita; porta TRUE = passa) com o COALESCE POR FORA do NOT, para que penalidade ausente reprove em vez de aprovar por acidente de negação. Os quatro limites são `var` com default no modelo (liquidez_min_casas=4, faixa_odd_min=1.50, faixa_odd_max=4.00, faixa_odd_dc_min=1.25, faixa_odd_dc_max=2.00), e o piso da DC é lido TAMBÉM pela `porta_odd_dc` já em vigor — o 1,25 existe num lugar só. ⚠️ As três chegam por append_new_columns, como as anteriores, e ficam NULL para sempre na linha de jogo já apitado antes deste deploy. `motivo_primario` NÃO as conhece: linha que só reprovaria nelas continua passando hoje, e dar-lhe um motivo seria descrever uma rejeição que não aconteceu.'
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

-- O DENOMINADOR CONGELADO (#105, ADR 0005): o p95 observado da nota de contexto por
-- (mercado, lado), medido uma vez sobre uma janela declarada e congelado em seed
-- versionado. É seed e não query de propósito — recalcular em runtime faria a régua
-- significar coisa diferente a cada dia e mataria toda comparação histórica.
denominador AS (
    SELECT market, lado, p95 FROM {{ ref('futebol_p95_nota_contexto') }}
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
-- Cobertura da Pinnacle = 1X2 inteiro precificado por ela (pin_n_outcomes >= 3),
-- INDEPENDENTE de qual fonte a linha realmente usou (Pinnacle ou fallback de
-- consenso) — o MESMO predicado que hoje é `WHERE d.pin_n_outcomes >= 3` no ramo do
-- board, virado coluna. Nome corrigido na #118: ver bloco de comentário antes de
-- `com_portas` para o porquê.
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
        COALESCE(d.pin_n_outcomes >= 3, FALSE)          AS porta_cobertura_pinnacle,
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
-- Cobertura da Pinnacle = par Over+Under precificado por ela na linha
-- (pin_n_outcomes >= 2), independente da fonte real da linha (#118).
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
        COALESCE(d.pin_n_outcomes >= 2, FALSE)          AS porta_cobertura_pinnacle,
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
-- complementar). Cobertura da Pinnacle = par precificado por ela (pin_n_outcomes
-- >= 2), independente da fonte real da linha (#118).
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
        COALESCE(d.pin_n_outcomes >= 2, FALSE)          AS porta_cobertura_pinnacle,
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
-- A Pinnacle NÃO precifica BTTS -> `pin_n_outcomes` fica NULL aqui, honestamente, e
-- a pergunta "a Pinnacle cobriu?" não se aplica: `porta_cobertura_pinnacle` é
-- TRIVIALMENTE TRUE, mesmo padrão de `porta_odd_dc`/`porta_linha_meia` num mercado
-- onde a porta não se aplica.
--
-- ⚠️ #118: até 28/08 esta porta usava `n_outcomes_valor >= 2` sob o nome de
-- "conjunto completo" — mas isso é o MESMO que `porta_valor_estimavel` já garante
-- (ADR 0002 exige n_outcomes_valor = conjunto_esperado, e 2 é o teto do BTTS, então
-- `>= 2` e `= 2` coincidem sempre). Medido em produção antes da troca: as duas
-- colunas concordam em 100% das 3.410 linhas de BTTS — zero divergência. A porta era
-- uma cópia disfarçada, não uma checagem própria; o valor real já vem de
-- `porta_valor_estimavel`, e trivializar aqui não muda `passou_no_gate` em nenhuma
-- linha, passada ou futura.
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
        TRUE                                             AS porta_cobertura_pinnacle,
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
-- A prob justa da DC é derivada do de-vig do 1X2 subjacente, e `pin_n_outcomes` não
-- existe nesse eixo — a pergunta "a Pinnacle cobriu?" não se aplica aqui do mesmo
-- jeito que no 1X2 direto: `porta_cobertura_pinnacle` é TRIVIALMENTE TRUE (#118, ver
-- o comentário equivalente no ramo BTTS — mesma redundância medida e confirmada
-- aqui: 5.034 linhas concordam em TRUE e 81 em FALSE com `porta_valor_estimavel`,
-- zero divergência). E a DC tem GATE DE ODD PRÓPRIO (best_odd >= 1,25), que hoje
-- mora no `WHERE` do ramo do board e aqui é a `porta_odd_dc`.
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
        TRUE                                             AS porta_cobertura_pinnacle,
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
-- ============================================================================
-- O LADO APOSTADO e o DENOMINADOR dele (#105, ADR 0005). Precisam vir ANTES da nota,
-- porque é o `p95` que a normalização divide.
--
-- ⚠️ `LEFT`, e não `INNER`. Lado fora do seed — ou saída não catalogada, cujo lado é
-- NULL por desenho — não pode sumir do funil: sumiço é o que a ADR 0006 proíbe, e é a
-- coisa inteira que esta tabela existe para impedir. O `p95` chega NULL, a normalização
-- o trata como denominador ausente (nota zero, explícita), e quem acende é a guarda
-- `assert_p95_nota_contexto_nao_derivou`, que cobra a cobertura dos onze lados.
--
-- O lado sai de `futebol_lado()` — num lugar só, lido também pela medição que produziu o
-- seed e pela guarda que o vigia. No Handicap ele NÃO é o `outcome`: é o sinal do
-- handicap na ótica do lado apostado, e os conjuntos de premissa de favorito e azarão são
-- disjuntos (Σ40 contra Σ30).
-- ============================================================================
com_lado AS (
    SELECT
        u.*,
        {{ futebol_lado('u.market', 'u.outcome', 'u.line_value') }} AS lado
    FROM unioned u
),

com_denominador AS (
    SELECT c.*, d.p95
    FROM com_lado c
    LEFT JOIN denominador d
        ON  d.market = c.market
       AND  d.lado   = c.lado
),

scored AS (
    SELECT
        *,
        (penalidades_globais_pts + penalidades_especificas_pts) AS penalidades,
        LEAST(GREATEST(
            pts_valor + pts_premissas + pts_corroboracao
            - (penalidades_globais_pts + penalidades_especificas_pts), 0), 100) AS score,
        -- A NOTA DE CONTEXTO (#103, ADR 0012), ao LADO da nota de hoje e não no lugar
        -- dela. É a nota depois que o preço sai: pontos de premissa menos as penalidades
        -- de CONTEXTO, com piso em zero. O board continua lendo o `score` acima — esta
        -- entrega mede no funil enquanto o produto segue no gate antigo, e a virada é uma
        -- só, no fim da [A].
        --
        -- A composição mora em `futebol_nota_contexto.sql`, num lugar só, e por dois
        -- motivos: a `assert_funil_nota_contexto_reconstroi` recompõe a coluna a partir
        -- das mesmas duas parcelas (cópia aqui = divergência muda entre modelo e guarda),
        -- e a `assert_nota_contexto_sem_preco` varre o TEXTO que o macro emite — escrever
        -- a soma aqui deixaria a sentinela vigiando um arquivo que ninguém usa.
        {{ futebol_nota_contexto() }} AS nota_contexto,
        -- linha "meia" (.5) é a única SEM push/meio-push. NULL onde não há linha.
        -- O predicado mora em `futebol_linha_meia.sql`, e não aqui, porque foi copiá-lo
        -- byte a byte do board que trouxe o defeito do `.25` para esta tabela (#101).
        {{ futebol_e_linha_meia('line_value') }} AS is_half_line
    FROM com_denominador
),

-- ============================================================================
-- A NOTA NORMALIZADA (#105, ADR 0005): a de contexto reescalada pelo p95 congelado do
-- lado, para que o 100 signifique a mesma coisa nos onze lados. Nasce AO LADO das outras
-- duas — o board segue no `score` e no gate de hoje, e a virada é uma só, no fim da [A].
--
-- A aritmética mora em `futebol_score_normalizado.sql`, num lugar só e sem argumento,
-- pelo mesmo motivo do macro da nota de contexto: argumento é porta de entrada para
-- reescalar a nota COM preço dentro. As duas colunas de que ele depende chegam com o nome
-- que ele espera — `nota_contexto`, da CTE acima, e `p95`, do seed.
--
-- ⚠️ CTE PRÓPRIA, e não mais uma linha da `scored`: no BigQuery um apelido do SELECT não
-- é visível para as outras expressões do MESMO SELECT, e `nota_contexto` é apelido de lá.
-- ============================================================================
com_nota_normalizada AS (
    SELECT
        *,
        {{ futebol_score_normalizado() }} AS score_normalizado
    FROM scored
),

-- ============================================================================
-- AS OITO PORTAS. TRUE = passou. Cada uma é NULL-safe SOZINHA — insumo ausente
-- reprova a porta em vez de propagar NULL para dentro da conjunção. É a degradação
-- graciosa do Motor, e é o que impede o descarte silencioso que a ADR 0006 proíbe.
--
-- ⚠️ RESOLVIDO (#118, opção 1 aplicada em 31/08): este parágrafo dizia que
-- `porta_conjunto_completo` e `porta_valor_estimavel` são ANINHADAS ("pela ADR 0002,
-- conjunto incompleto implica prob justa ausente") e avisava contra somá-las. Os dados
-- diziam o contrário — elas eram quase DISJUNTAS em AH/Gols — porque o nome escondia
-- DOIS predicados diferentes por trás de UM só:
--
--   | mercado          | valor_fonte | completo | estimavel | linhas |
--   |------------------|-------------|----------|-----------|--------|
--   | asian_handicap   | consenso    | false    | TRUE      |  9.102 |
--   | goals_over_under | consenso    | false    | TRUE      | 10.644 |
--
-- A porta virou `porta_cobertura_pinnacle`, que é o que ela sempre testou em
-- 1X2/Gols/Handicap: `pin_n_outcomes >= N`, "a PINNACLE cobriu?" — independente da
-- fonte real da linha. A Pinnacle não precifica BTTS nem tem eixo próprio na Dupla
-- Chance, então nesses dois mercados a pergunta não se aplica e a porta é
-- TRIVIALMENTE TRUE (mesmo padrão de `porta_odd_dc` fora da DC): o predicado antigo
-- daqueles dois ramos (`n_outcomes_valor >= N`) provou ser uma cópia disfarçada de
-- `porta_valor_estimavel` — zero divergência medida em 8.525 linhas de BTTS+DC — e
-- não precisava de porta própria. `passou_no_gate` não muda em NENHUMA linha, passada
-- ou futura: só o nome deixou de mentir sobre o que a coluna testa.
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
        -- ⚠️ O 1,25 saiu do literal e passou a ser lido da MESMA var que a faixa da A5 usa
        -- como piso da DC (#104): o número existe num lugar só, e mexer nele não pode mover
        -- uma porta e deixar a outra para trás.
        COALESCE(
            market <> '{{ futebol_mercados_pontuados()[12] }}'
            OR best_odd >= {{ var('faixa_odd_dc_min', 1.25) }},
            FALSE)                                          AS porta_odd_dc,

        -- ====================================================================
        -- AS TRÊS BARREIRAS DE PREÇO DA [A3+A5] (#104) — MEDIDAS, FORA DA CONJUNÇÃO.
        --
        -- Elas dizem quem PASSARIA, sem ainda remover ninguém do board. Quem as põe em
        -- vigor é a virada (#109), acrescentando-as à conjunção logo abaixo; nesta entrega
        -- o board não muda de volume nem de composição.
        --
        -- ⚠️ POR QUE `porta_liquidez_estrita` E NÃO `porta_liquidez` COM O MÍNIMO EM 4,
        -- que é o que a spec da #104 pede literalmente. Redefinir a `porta_liquidez` no
        -- lugar tem três saídas e as três quebram um aceite:
        --   (a) mínimo 4 E dentro da conjunção -> o board perde as linhas de exatamente 3
        --       casas, contra o aceite "não muda de volume nem de composição";
        --   (b) mínimo 4 E fora da conjunção -> o gate fica SEM termo de liquidez nenhum,
        --       linha de 1-2 casas passa, e a `assert_funil_paridade_com_board` fica
        --       vermelha contra um board que não mudou;
        --   (c) redefinir de qualquer jeito -> o funil é APPEND-ONLY. Um nome de coluna
        --       passaria a valer >= 3 nas linhas já congeladas e >= 4 nas novas, para
        --       sempre, dentro do registro de época. É o rótulo mentiroso da #118
        --       reproduzido de propósito, e no lugar onde não dá para desfazer.
        -- As duas convivem, portanto, e a virada troca qual delas está na conjunção — sem
        -- renomear nada, que é o único jeito de não mentir sobre o passado.
        --
        -- ⚠️ POLARIDADE: `pen_odd_outlier` é TRUE quando a linha é SUSPEITA; porta é TRUE
        -- quando a linha PASSA. Daí o NOT, e o COALESCE por FORA dele — penalidade ausente
        -- (NULL) tem de REPROVAR a barreira, não aprová-la por acidente de negação.
        --
        -- ⚠️ FRONTEIRAS INCLUSIVAS NAS DUAS PONTAS (`>=` e `<=`): odd exatamente 1,50, 4,00,
        -- 1,25 ou 2,00 PASSA. Está escrito porque neste repo já houve knife-edge de float
        -- (a #92) e porque "faixa 1,50–4,00" não diz sozinho o que acontece na fronteira.
        --
        -- ⚠️ As três chegam por `append_new_columns` e SÓ nas linhas que o congelamento
        -- ainda deixa gravar: linha de jogo já apitado antes deste deploy fica com elas
        -- NULL para sempre. É o append-only funcionando (ADR 0011), não defeito — igual ao
        -- que aconteceu com `nota_contexto` na A1 e com `score_normalizado` na A6.
        -- ====================================================================
        COALESCE(n_casas >= {{ var('liquidez_min_casas', 4) }}, FALSE)
                                                            AS porta_liquidez_estrita,
        COALESCE(NOT pen_odd_outlier, FALSE)                AS porta_outlier,
        COALESCE(
            best_odd >= CASE WHEN market = '{{ futebol_mercados_pontuados()[12] }}'
                             THEN {{ var('faixa_odd_dc_min', 1.25) }}
                             ELSE {{ var('faixa_odd_min', 1.50) }} END
            AND
            best_odd <= CASE WHEN market = '{{ futebol_mercados_pontuados()[12] }}'
                             THEN {{ var('faixa_odd_dc_max', 2.00) }}
                             ELSE {{ var('faixa_odd_max', 4.00) }} END,
            FALSE)                                          AS porta_faixa_odd
    FROM com_nota_normalizada
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
--
-- ⚠️ A VIRADA (#109), executada aqui: `porta_liquidez_estrita`, `porta_outlier` e
-- `porta_faixa_odd` ENTRAM na conjunção; `porta_liquidez` (>= 3), `porta_edge` e
-- `porta_nota` SAEM dela. As três que saem continuam colunas — o funil é append-only e
-- um booleano medido não deixa de existir por deixar de valer — só param de eliminar.
-- O `score`/nota deixa de ser precondição: a régua de 40 vira informação, não gate, e é
-- por isso que `porta_nota` sai da conjunção em vez de ganhar um novo corte. O mesmo vale
-- para `porta_edge`: preço deixou de ser precondição na #103/#109, só ainda não estava em
-- vigor até este commit.
-- ============================================================================
com_gate AS (
    SELECT
        *,
        (   porta_saida_catalogada
        AND porta_cobertura_pinnacle
        AND porta_valor_estimavel
        AND porta_liquidez_estrita
        AND porta_linha_meia
        AND porta_odd_dc
        AND porta_outlier
        AND porta_faixa_odd ) AS passou_no_gate
    FROM com_portas
)

SELECT
    fixture_id,
    market,
    outcome,
    -- O LADO APOSTADO (#105, ADR 0005) — o eixo do denominador congelado, e o que o
    -- `outcome` sozinho não diz. No Handicap Home/Away não separa quem dá e quem recebe o
    -- handicap, e os conjuntos de premissa dos dois são disjuntos; na Dupla Chance 1X e X2
    -- dividem as quatro premissas e colapsam em `unico`. NULL na saída não catalogada (a
    -- "12"), pelo mesmo fail-closed do `futebol_market_slug`.
    lado,
    line_value,
    -- A CHAVE DO MERGE, e ela existe por um motivo mecânico: `line_value` é NULL no 1X2,
    -- no BTTS e na Dupla Chance, e num MERGE ... ON, NULL nunca casa com NULL. Com
    -- `line_value` cru na `unique_key` toda linha desses três mercados seria INSERIDA de
    -- novo a cada execução, em silêncio, até a guarda de grão acender. O `COALESCE` para
    -- 'NONE' é o mesmo que os dois lados das guardas já usam.
    COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key,
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

    -- ------------------------------------------------- as oito portas EM VIGOR
    porta_saida_catalogada,
    porta_cobertura_pinnacle,
    porta_valor_estimavel,
    porta_liquidez,
    porta_edge,
    porta_nota,
    porta_linha_meia,
    porta_odd_dc,
    passou_no_gate,

    -- ------------------------------------- as três barreiras MEDIDAS (#104, A3+A5)
    -- Fora de `passou_no_gate` até a virada (#109). Ver o bloco de comentário na CTE
    -- `com_portas` para por que a de liquidez tem nome próprio em vez de redefinir a
    -- `porta_liquidez` — resumo: o funil é append-only e um nome não pode valer duas
    -- coisas em duas eras da mesma tabela.
    porta_liquidez_estrita,
    porta_outlier,
    porta_faixa_odd,

    -- CONVENIÊNCIA DE LEITURA, NÃO FONTE (ADR 0006). Uma linha reprova em várias portas
    -- ao mesmo tempo, e um campo único de motivo é vitória do primeiro da fila: ele
    -- destrói exatamente a distinção que dá valor à tabela — quantas linhas a porta
    -- remove SOZINHA contra quantas ela ainda remove DEPOIS das anteriores. Quem for
    -- medir porta lê os booleanos; isto aqui serve para olhar uma linha e entender.
    --
    -- A ordem é a de leitura declarada na ADR 0011 (D5), e o empate tem lugar próprio
    -- dentro da porta de nota: sem ele, um terço do universo do 1X2 apareceria como
    -- "nota abaixo da régua" e a régua pareceria mais severa no 1X2 do que é.
    -- ⚠️ #109: `porta_edge` e `porta_nota` saem da ladder — não eliminam mais, e o ramo do
    -- empate (`sem_lado_apostado`) saía justamente do NOT porta_nota; sem ela, o empate do
    -- 1X2 passa a poder publicar (score 0, faixa Baixa), e a coluna `sem_lado_apostado`
    -- segue informativa em vez de motivo de corte. `sem_liquidez`/`sem_edge`/
    -- `nota_abaixo_da_regua`/`sem_lado_apostado` seguem no accepted_values como LEGADO —
    -- toda linha travada nessas portas antes deste deploy carrega o valor para sempre
    -- (ADR 0011). `sem_liquidez_estrita`, `odd_outlier` e `faixa_odd_fora` são os três
    -- valores novos, um por barreira que entrou na conjunção.
    CASE
        WHEN NOT porta_saida_catalogada   THEN 'saida_nao_catalogada'
        WHEN NOT porta_cobertura_pinnacle THEN 'sem_cobertura_pinnacle'
        WHEN NOT porta_valor_estimavel    THEN 'valor_nao_estimavel'
        WHEN NOT porta_liquidez_estrita   THEN 'sem_liquidez_estrita'
        WHEN NOT porta_linha_meia         THEN 'linha_nao_meia'
        WHEN NOT porta_odd_dc             THEN 'odd_dc_abaixo_do_minimo'
        WHEN NOT porta_outlier            THEN 'odd_outlier'
        WHEN NOT porta_faixa_odd          THEN 'faixa_odd_fora'
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
    -- A NOTA DE CONTEXTO (#103, ADR 0012). Nasce AO LADO do `score`, não no lugar dele:
    -- nesta entrega o board não muda de gate nem de número, e quem lê esta coluna é a
    -- medição da [A]. NULL — e não zero — onde não houve premissa a avaliar, pelo mesmo
    -- motivo que o `score` (ADR 0003).
    nota_contexto,
    -- A NOTA NORMALIZADA (#105, ADR 0005). A de contexto dividida pelo p95 CONGELADO do
    -- lado, em 0–100, para que o 100 signifique a mesma coisa nos onze lados. Absoluta —
    -- quanta evidência acendeu —, nunca percentil dentro do lado.
    --
    -- ⚠️ ~5% das linhas de cada lado batem em 100 POR CONSTRUÇÃO: o denominador é o
    -- quantil 95, o `LEAST(100, ...)` as trava ali, e isso não é erro.
    -- ⚠️ Denominador zero (empate do 1X2, Pick do Handicap) ⇒ ZERO explícito, nunca NULL:
    -- NULL faria a comparação com a régua virar NULL e a linha sairia sem passar e sem ser
    -- marcada, que é o descarte silencioso que a ADR 0006 proíbe. NULL aqui só onde não
    -- houve premissa a avaliar, como no `score` e na `nota_contexto` (ADR 0003).
    -- ⚠️ NÃO é o número do board. O board segue no `score` e no gate de 40 até a virada.
    score_normalizado,
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

    -- ----------------------------------------------------------------- os carimbos (#96)
    -- QUANDO o Motor disse isto. Sob append-only, "quando o dbt carregou" e "quando ficou
    -- registrado" são o MESMO instante — por isso este campo substituiu o `dbt_loaded_at`
    -- em vez de conviver com ele. Duas colunas de tempo com o mesmo valor são duas colunas
    -- que um dia divergem e ninguém sabe qual manda.
    CURRENT_TIMESTAMP()         AS gravado_em,
    -- DE ONDE ela veio. `backfill` é o build que CRIA a tabela: aquelas linhas foram
    -- recalculadas com o código de hoje sobre odds antigas, e são a única parte do funil
    -- que NÃO é registro do que foi dito na época — têm de dizer isso de si mesmas. Toda
    -- escrita incremental é `corrente`, e essa sim é registro de época.
    --
    -- ⚠️ Uma linha `backfill` de jogo ainda futuro vira `corrente` no primeiro merge
    -- seguinte. É o comportamento certo: ela voltou a ser escrita antes do apito, então
    -- passou a ser registro de época de verdade.
    '{{ 'corrente' if is_incremental() else 'backfill' }}' AS origem
FROM com_gate
-- LEFT, nunca INNER: fixture ausente em `fact_fixtures` não pode sumir do funil — sumir
-- seria a perda silenciosa que a tabela inteira existe para impedir, e quebraria a
-- reconciliação contra o de-vig. O kickoff vem NULL e diz isso de si mesmo.
LEFT JOIN fixtures USING (fixture_id)
{% if is_incremental() %}
-- ============================================================================
-- O CONGELAMENTO (#96, ADR 0011). É esta linha, e só ela, que transforma a tabela de
-- foto em registro: o merge só recebe candidato de jogo que AINDA NÃO COMEÇOU, então
-- nenhuma linha de kickoff passado é reescrita por build nenhum nem por deploy nenhum.
--
-- O predicado mora em `futebol_funil.sql` — o mesmo que as duas guardas leem. Copiá-lo
-- aqui faria dele cinco cópias, e cópia que diverge do que a guarda espera é divergência
-- MUDA nos dois sentidos (ver o cabeçalho do macro).
-- ============================================================================
WHERE {{ futebol_funil_e_gravavel('_fx_kickoff_utc') }}
{% endif %}
