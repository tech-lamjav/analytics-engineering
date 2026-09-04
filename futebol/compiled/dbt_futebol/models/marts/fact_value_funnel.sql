

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
    -- OS CINCO MERCADOS PONTUADOS. O 6 (Gols O/U do 1º tempo) é coletado e passa pelo
    -- de-vig, mas não tem modelo de premissa: gravá-lo como "rejeitado" registraria como
    -- decisão nossa a ausência de um modelo que nunca escrevemos (ADR 0011).
    WHERE market_id IN (1, 4, 5, 8, 12)
),

-- A corroboração já vem reduzida à janela corrente e com grão (fixture, mercado, saída,
-- linha) — sem janela. O join abaixo, portanto, é o MESMO do board: a linha de t24h e a
-- de t15m recebem a mesma corroboração. Não é descuido do funil, é o grão do modelo a
-- montante, e mudá-lo aqui quebraria a paridade.
corro AS (
    SELECT
        *,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM `smartbetting-dados`.`futebol`.`int_futebol_corroboracao`
),

prem_1x2 AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
),

prem_ou AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou`
),

prem_ah AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
),

prem_btts AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts`
),

prem_dc AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
),

-- O DENOMINADOR CONGELADO (#105, ADR 0005; declarado em vez de medido desde a PPP#365,
-- ADR 0013): o teto de pontos do catálogo por (mercado, lado) — a soma dos pesos
-- máximos de todas as premissas do lado, lida dos cinco modelos de premissa e não
-- recalculada em runtime. O seed do p95 (`futebol_p95_nota_contexto`) continua no
-- repositório como registro de como o denominador era medido antes; não é mais lido
-- aqui.
denominador AS (
    SELECT market, lado, teto FROM `smartbetting-dados`.`futebol`.`futebol_teto_nota_contexto`
),

-- SÓ O KICKOFF, e o status DE PROPÓSITO fora (ADR 0011, D10). O kickoff é o que o
-- congelamento da próxima entrega vai usar e o que toda análise por horizonte precisa;
-- o status muda DEPOIS do apito, e uma linha congelada carregando o status de antes
-- mentiria. Quem quiser status junta `fact_fixtures` — que é onde ele está certo.
fixtures AS (
    SELECT
        fixture_id,
        kickoff_utc AS _fx_kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
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
        'match_winner'         AS market,
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
        'goals_over_under'         AS market,
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
        'asian_handicap'         AS market,
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
        'btts'         AS market,
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
        'double_chance'        AS market,
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
-- O LADO APOSTADO e o DENOMINADOR dele (#105, ADR 0005; teto do catálogo desde a
-- PPP#365, ADR 0013). Precisam vir ANTES da nota, porque é o `teto` que a normalização
-- divide.
--
-- ⚠️ `LEFT`, e não `INNER`. Lado fora do seed — ou saída não catalogada, cujo lado é
-- NULL por desenho — não pode sumir do funil: sumiço é o que a ADR 0006 proíbe, e é a
-- coisa inteira que esta tabela existe para impedir. O `teto` chega NULL, a
-- normalização o trata como denominador ausente (nota zero, explícita). ⚠️ Este PR não
-- trouxe guarda de cobertura para o teto (a antiga, `assert_p95_nota_contexto_nao_derivou`,
-- foi rebaixada a `warn` — ela vigiava o p95, que não é mais o denominador vivo).
--
-- O lado sai de `futebol_lado()` — num lugar só, lido também pela medição que produziu o
-- seed e pela guarda que o vigia. No Handicap ele NÃO é o `outcome`: é o sinal do
-- handicap na ótica do lado apostado, e os conjuntos de premissa de favorito e azarão são
-- disjuntos (Σ40 contra Σ30).
-- ============================================================================
-- PARTITION BY não aceita FLOAT64 (line_value): CAST p/ STRING, mesma conversão que
-- `futebol_devig_todas_janelas()._line_key` usa pro mesmo motivo.
com_lado AS (
    SELECT
        u.*,
        CASE u.market
        WHEN 'match_winner' THEN
            IF(u.outcome IN ('Home', 'Draw', 'Away'), u.outcome, NULL)
        WHEN 'goals_over_under' THEN
            IF(u.outcome IN ('Over', 'Under'), u.outcome, NULL)
        WHEN 'btts' THEN
            IF(u.outcome IN ('Yes', 'No'), u.outcome, NULL)
        WHEN 'double_chance' THEN
            IF(u.outcome IN ('1X', 'X2'), 'unico', NULL)
        WHEN 'asian_handicap' THEN
            CASE
                WHEN u.outcome NOT IN ('Home', 'Away') THEN NULL
                -- o handicap na ótica do lado apostado; `line_value` vem na do mandante.
                WHEN IF(u.outcome = 'Home', u.line_value, -u.line_value) < 0 THEN 'Favorito'
                WHEN IF(u.outcome = 'Home', u.line_value, -u.line_value) > 0 THEN 'Azarao'
                -- linha 0 (B3, #109): a odd decide quem é favorito, mando só desempata
                -- odds iguais (ou ausentes). MESMA regra em `int_futebol_premissas_ah`
                -- (is_favorito/is_azarao); os dois têm de concordar, porque é esta coluna
                -- que casa a linha com o p95 do lado.
                WHEN IF(u.outcome = 'Home', u.line_value, -u.line_value) = 0
                    THEN IF(
                        COALESCE((ROW_NUMBER() OVER (  PARTITION BY u.fixture_id, u.market, COALESCE(CAST(u.line_value AS STRING), 'NONE'), u.janela_usada  ORDER BY u.best_odd ASC, IF(u.outcome = 'Home', 0, 1) ASC) = 1), u.outcome = 'Home'),
                        'Favorito', 'Azarao'
                    )
                -- handicap ausente: não dá para dizer o lado, e inventá-lo é pior.
                ELSE NULL
            END
    END AS lado
    FROM unioned u
),

com_denominador AS (
    SELECT c.*, d.teto
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
        GREATEST(pts_premissas - penalidades_especificas_pts, 0) AS nota_contexto,
        -- linha "meia" (.5) é a única SEM push/meio-push. NULL onde não há linha.
        -- O predicado mora em `futebol_linha_meia.sql`, e não aqui, porque foi copiá-lo
        -- byte a byte do board que trouxe o defeito do `.25` para esta tabela (#101).
        (MOD(CAST(ROUND(ABS(line_value) * 4) AS INT64), 4) = 2) AS is_half_line
    FROM com_denominador
),

-- ============================================================================
-- A NOTA NORMALIZADA (#105, ADR 0005): a de contexto reescalada pelo teto do catálogo
-- congelado do lado (PPP#365, ADR 0013), para que o 100 signifique a mesma coisa nos
-- onze lados. Nasce AO LADO das outras duas — o board segue no `score` e no gate de
-- hoje, e a virada é uma só, no fim da [A].
--
-- A aritmética mora em `futebol_score_normalizado.sql`, num lugar só e sem argumento,
-- pelo mesmo motivo do macro da nota de contexto: argumento é porta de entrada para
-- reescalar a nota COM preço dentro. As duas colunas de que ele depende chegam com o nome
-- que ele espera — `nota_contexto`, da CTE acima, e `teto`, do seed.
--
-- ⚠️ CTE PRÓPRIA, e não mais uma linha da `scored`: no BigQuery um apelido do SELECT não
-- é visível para as outras expressões do MESMO SELECT, e `nota_contexto` é apelido de lá.
-- ============================================================================
com_nota_normalizada AS (
    SELECT
        *,
        CASE
        WHEN nota_contexto IS NULL      THEN NULL
        WHEN teto IS NULL OR teto <= 0  THEN 0
        ELSE LEAST(100, CAST(ROUND(nota_contexto / teto * 100) AS INT64))
    END AS score_normalizado
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
                     WHEN valor_fonte = 'consenso' THEN 0.03
                     ELSE 0
                   END,
            FALSE)                                          AS porta_edge,
        COALESCE(score >= 40, FALSE)                        AS porta_nota,
        -- Handicap e Gols exigem linha meia (.5): nas outras o resultado pode dar
        -- push/meio-push e o de-vig 2-way superdimensiona o edge. Mercado sem linha
        -- passa trivialmente — não é isenção, é que a porta não se aplica.
        COALESCE(
            market NOT IN ('asian_handicap',
                           'goals_over_under') OR is_half_line,
            FALSE)                                          AS porta_linha_meia,
        -- Gate de odd próprio da Dupla Chance. Trivialmente TRUE nos outros quatro.
        -- ⚠️ O 1,25 saiu do literal e passou a ser lido da MESMA var que a faixa da A5 usa
        -- como piso da DC (#104): o número existe num lugar só, e mexer nele não pode mover
        -- uma porta e deixar a outra para trás.
        COALESCE(
            market <> 'double_chance'
            OR best_odd >= 1.25,
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
        COALESCE(n_casas >= 4, FALSE)
                                                            AS porta_liquidez_estrita,
        COALESCE(NOT pen_odd_outlier, FALSE)                AS porta_outlier,
        COALESCE(
            best_odd >= CASE WHEN market = 'double_chance'
                             THEN 1.25
                             ELSE 1.5 END
            AND
            best_odd <= CASE WHEN market = 'double_chance'
                             THEN 2.0
                             ELSE 4.0 END,
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
    -- A NOTA NORMALIZADA (#105, ADR 0005). A de contexto dividida pelo TETO DO CATÁLOGO
    -- congelado do lado (PPP#365, ADR 0013), em 0–100, para que o 100 signifique a mesma
    -- coisa nos onze lados. Absoluta — quanta evidência acendeu —, nunca percentil
    -- dentro do lado.
    --
    -- ⚠️ Bate em 100 só quando TODAS as premissas do lado acendem juntas — raro na
    -- maioria dos lados, mas o `LEAST(100, ...)` continua explícito porque nada no
    -- catálogo impede a coincidência.
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
    'corrente' AS origem
FROM com_gate
-- LEFT, nunca INNER: fixture ausente em `fact_fixtures` não pode sumir do funil — sumir
-- seria a perda silenciosa que a tabela inteira existe para impedir, e quebraria a
-- reconciliação contra o de-vig. O kickoff vem NULL e diz isso de si mesmo.
LEFT JOIN fixtures USING (fixture_id)

-- ============================================================================
-- O CONGELAMENTO (#96, ADR 0011). É esta linha, e só ela, que transforma a tabela de
-- foto em registro: o merge só recebe candidato de jogo que AINDA NÃO COMEÇOU, então
-- nenhuma linha de kickoff passado é reescrita por build nenhum nem por deploy nenhum.
--
-- O predicado mora em `futebol_funil.sql` — o mesmo que as duas guardas leem. Copiá-lo
-- aqui faria dele cinco cópias, e cópia que diverge do que a guarda espera é divergência
-- MUDA nos dois sentidos (ver o cabeçalho do macro).
-- ============================================================================
WHERE COALESCE(_fx_kickoff_utc > CURRENT_TIMESTAMP(), TRUE)
