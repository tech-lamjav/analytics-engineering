
-- GUARDA 1 DO EXPURGO DO BOARD (#85, ADR 0009): o `fact_value_opportunities` não emite
-- linha de jogo que já saiu da janela do que dá para apostar.
--
-- Ela existe porque o aceite da ADR 0009 é MEDIDO, não afirmado. O defeito que a decisão
-- corrige é exatamente do tipo que volta sozinho: basta alguém reescrever o filtro final
-- do mart, ou trocar o LEFT JOIN de lugar, e o board recomeça a reemitir jogo de junho —
-- sem erro, sem linha vermelha, com o app continuando a servir 200.
--
-- ⚠️ O PREDICADO NÃO É COPIADO. Ele vem de `macros/futebol_expurgo.sql`, o mesmo que o
-- mart usa. Guarda que reescreve à mão a regra que fiscaliza tem dois modos de falha e os
-- dois são mudos: mais frouxa que o mart, nunca acende; mais estrita, acende sem defeito.
--
-- TRÊS DIAGNÓSTICOS, e eles não são a mesma falha:
--
--   · status terminal ou ao vivo — o expurgo por status parou de acontecer. É a regressão
--     direta da ADR 0009;
--   · kickoff + carência sem status final — o expurgo por status está de pé, mas a rede de
--     segurança não. Aqui o dedo aponta para a COLETA DE PLACAR (task [C]), não para este
--     mart: o jogo aconteceu e ninguém carimbou o status;
--   · fixture ausente em `fact_fixtures` — a linha passou pelo fail-open do mart. Não é
--     defeito do expurgo (a ADR 0003 manda mesmo deixar passar), é defeito a montante, e
--     esta guarda é o único lugar onde ele grita. Sem este ramo o fail-open seria um buraco
--     por onde jogo encerrado voltaria ao board em silêncio, que é o oposto do que a
--     decisão quer.
--
-- ⚠️ PST/SUSP/INT sobrevivem inclusive além da carência, e é por isso que a exceção está
-- dentro do macro e não aqui: jogo adiado fica adiado por semanas, e uma guarda que a
-- ignorasse acenderia vermelha em cima da linha que a decisão manda preservar.
--
-- ⚠️ PONTO CEGO DECLARADO: esta guarda reavalia `CURRENT_TIMESTAMP()` na fase 4, minutos
-- depois de o mart tê-lo avaliado na fase 2. Uma linha que cruzar a fronteira da carência
-- DENTRO dessa janela acende vermelho uma vez sem defeito nenhum de código, e se cura
-- sozinha no run seguinte (o mart a expurga). Não vale sincronizar relógio entre as fases
-- para evitar isso: o custo seria carimbar um "agora" no mart — coluna nova em tabela
-- sincronizada, que é exatamente o que a ADR 0009 recusou —, e o falso positivo é raro,
-- transitório e legível pelo diagnóstico, que aponta a carência e não o status.

SELECT
    o.fixture_id,
    o.market,
    o.outcome,
    o.line_value,
    f.status_short,
    f.kickoff_utc,
    CASE
        WHEN f.fixture_id IS NULL
            THEN 'fixture ausente em fact_fixtures — a linha entrou pelo fail-open do mart (ADR 0003). Defeito a montante, não do expurgo, mas o board está publicando linha que ninguém consegue validar'
        WHEN f.status_short IN ('FT', 'AET', 'PEN', 'CANC', 'ABD', 'AWD', 'WO')
            THEN 'jogo com status terminal ainda no board — o expurgo por status parou de acontecer (regressão da ADR 0009)'
        WHEN f.status_short IN ('1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE')
            THEN 'jogo ao vivo ainda no board — não se aposta pré-jogo com a bola rolando (regressão da ADR 0009)'
        ELSE FORMAT(
            'kickoff passou de %d h e o jogo nunca recebeu status final (está em %s) — a rede de segurança do expurgo não pegou. O dedo aponta para a coleta de placar (task [C]), não para este mart',
            24,
            COALESCE(f.status_short, 'NULL')
        )
    END AS diagnostico
FROM `smartbetting-dados`.`futebol`.`fact_value_opportunities` o
LEFT JOIN `smartbetting-dados`.`futebol`.`fact_fixtures` f
       ON f.fixture_id = o.fixture_id
WHERE f.fixture_id IS NULL
   OR (
        f.status_short IN ('FT', 'AET', 'PEN', 'CANC', 'ABD', 'AWD', 'WO', '1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE')
        OR (
            TIMESTAMP_ADD(f.kickoff_utc, INTERVAL 24 HOUR)
                < CURRENT_TIMESTAMP()
            -- COALESCE, e não `f.status_short NOT IN (...)` direto: status nulo tem de
            -- ser alcançado pela carência, não escapar dela por NULL. Ver o cabeçalho.
            AND COALESCE(f.status_short, '') NOT IN ('PST', 'SUSP', 'INT')
        )
    )