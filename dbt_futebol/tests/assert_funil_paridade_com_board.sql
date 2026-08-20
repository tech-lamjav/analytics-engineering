{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE PARIDADE FUNIL x BOARD (#95, ADR 0011): a prova de que o funil descreve o
-- board de verdade — tirada ANTES de qualquer um passar a depender dele.
--
-- Enquanto o passo 2 (o flip) não acontece, a nota e as portas existem em DOIS lugares: no
-- `fact_value_opportunities`, onde são `WHERE`, e no `fact_value_funnel`, onde são coluna.
-- Duas cópias da mesma aritmética divergem — é o que cópias fazem. Esta guarda é o que
-- torna a divergência barulhenta em vez de muda, e ela é o motivo pelo qual a duplicação é
-- aceitável nesta entrega.
--
-- Ela é **ASSIMÉTRICA DE PROPÓSITO**, e as duas direções valem coisas diferentes:
--
--   · DIREÇÃO 1 (vale sempre) — toda linha do board existe idêntica no funil, com a MESMA
--     janela e a MESMA nota. Se o funil perder uma linha que o board publica, ou pontuá-la
--     diferente, a leitura de "quanto rendeu a faixa descartada" está sendo feita sobre
--     outra tabela que não a que o assinante viu;
--
--   · DIREÇÃO 2 (restrita) — o funil filtrado por `janela_e_corrente AND passou_no_gate`
--     não tem linha fora do board **entre os fixtures que ainda não foram expurgados**.
--     A restrição não é conveniência: o funil guarda jogo encerrado DE PROPÓSITO (ADR
--     0011) e o board não (ADR 0009, #85). Sem ela, a guarda ficaria vermelha para sempre
--     por acerto das duas tabelas, e guarda permanentemente vermelha morre ignorada.
--
-- O predicado do expurgo vem do macro `futebol_expurgo.sql`, o mesmo que o board usa —
-- nunca copiado. Predicado copiado diverge, e aqui a divergência seria muda nos dois
-- sentidos: mais frouxo e a guarda não acende, mais estrito e ela acende sem defeito.
--
-- ⚠️ O expurgo é função de `CURRENT_TIMESTAMP()`, e a guarda roda DEPOIS do build. Um jogo
-- que cruzou a carência de 24 h entre o build do board e esta execução sai do lado do
-- expurgo aqui e a linha é (corretamente) ignorada. A janela oposta — jogo que era
-- expurgável no build e deixou de ser — só existe via PST/SUSP reabrindo, e nela a guarda
-- acusa uma diferença real de conteúdo entre as duas tabelas.
--
-- ⚠️ ESTA GUARDA TEM DATA DE VALIDADE. No passo 2 o board passa a ser o funil filtrado, a
-- paridade vira tautologia e ela é APOSENTADA no mesmo commit. Guarda que não pode falhar
-- é ruído com cara de cobertura.

WITH board AS (
    SELECT
        fixture_id,
        market,
        outcome,
        COALESCE(CAST(line_value AS STRING), 'NONE')    AS line_key,
        janela_usada                                    AS janela,
        score
    FROM {{ ref('fact_value_opportunities') }}
),

fixtures AS (
    SELECT
        fixture_id,
        status_short AS _fx_status_short,
        kickoff_utc  AS _fx_kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

-- O funil na leitura que o board faria: janela corrente, gate aprovado, e — só para a
-- direção 2 — sem os fixtures que o board expurga.
funil_publicavel AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        COALESCE(CAST(f.line_value AS STRING), 'NONE')  AS line_key,
        f.janela,
        f.score
    FROM {{ ref('fact_value_funnel') }} f
    -- LEFT + COALESCE(..., FALSE): fixture ausente é fail-open aqui pelo mesmo motivo que
    -- é fail-open no board — a linha fica, e quem grita sobre fixture ausente é a
    -- assert_board_sem_jogo_encerrado, que tem diagnóstico próprio para isso.
    LEFT JOIN fixtures fx USING (fixture_id)
    WHERE f.janela_e_corrente
      AND f.passou_no_gate
      AND NOT COALESCE(
            {{ futebol_expurga_do_board('fx._fx_status_short', 'fx._fx_kickoff_utc') }},
            FALSE
          )
)

SELECT
    *,
    'linha publicada no board que o funil não reproduz (ausente, ou com janela/nota diferente) — as duas cópias da aritmética divergiram' AS diagnostico
FROM (
    SELECT * FROM board
    EXCEPT DISTINCT
    SELECT * FROM funil_publicavel
)

UNION ALL

SELECT
    *,
    'linha que o funil publicaria e o board não publica, em fixture NÃO expurgado — o funil está mais frouxo que o board (porta virada coluna com predicado diferente?)' AS diagnostico
FROM (
    SELECT * FROM funil_publicavel
    EXCEPT DISTINCT
    SELECT * FROM board
)
