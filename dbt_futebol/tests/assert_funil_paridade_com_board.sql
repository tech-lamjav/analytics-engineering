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
-- ⚠️ O QUE ELA NÃO COBRE, e é preciso dizer em voz alta: as duas direções comparam só o
-- conjunto PUBLICÁVEL. Uma divergência de fórmula confinada às linhas REJEITADAS — que são
-- justamente o produto novo desta tabela — passa por aqui em silêncio nas duas direções,
-- porque nenhum dos dois lados as contém. Quem alcança essa região são os unit tests do
-- `fact_value_funnel`, com linha construída. A guarda impede as duas cópias de divergirem
-- onde o assinante enxerga; não onde a análise da [A] vai olhar.
--
-- ⚠️ ESCOPADA AO JOGO QUE AINDA NÃO COMEÇOU (#96), e sem isso ela não sobreviveria ao
-- congelamento. Desde a ADR 0011 as duas tabelas param de andar juntas no instante do
-- apito: o funil congela a linha ali e o board CONTINUA recalculando a dele até o expurgo
-- levá-la — o que só acontece quando o status vira ao vivo ou terminal, ou quando a
-- carência de 24 h vence. Nessa fresta o board relê premissas que foram recoletadas
-- depois do apito, e a #78 já mostrou premissa que acende em número diferente de linhas a
-- cada build com o insumo congelado. As duas tabelas divergiriam ali por acerto das duas,
-- e a guarda acenderia vermelha sobre o comportamento que a ADR 0011 mandou construir.
--
-- O escopo é o mesmo predicado que governa a escrita do funil — kickoff no futuro, ou
-- kickoff desconhecido (fail-open dos dois lados: o board não expurga fixture ausente e o
-- funil não para de gravá-lo). Dentro dele a paridade continua sendo a igualdade EXATA de
-- payload que o aceite da #95 pediu, e é onde ela vale: é o conjunto que o assinante
-- ainda pode apostar.
--
-- ⚠️ O que sai junto com o escopo: uma divergência de fórmula que só aparecesse em jogo já
-- apitado passa por aqui em silêncio. Não há como ser diferente — depois do apito não
-- existe mais um par comparável, porque um dos dois lados parou no tempo de propósito.
--
-- ⚠️ ESTA GUARDA TEM DATA DE VALIDADE. No passo 2 o board passa a ser o funil filtrado, a
-- paridade vira tautologia e ela é APOSENTADA no mesmo commit. Guarda que não pode falhar
-- é ruído com cara de cobertura.

-- "IDÊNTICA" É A PALAVRA DO ACEITE, ENTÃO A COMPARAÇÃO É O PAYLOAD INTEIRO, não só a
-- chave e a nota. A nota agrega os componentes: `edge`, o contexto de odds e as quatro
-- parcelas da penalidade podem divergir sem mover um ponto sequer — `pts_valor` é o edge
-- passado por um `ROUND` de faixa, e três das quatro penalidades não mudam a soma se duas
-- trocarem de lugar. Comparar a nota sozinha seria confiar num proxy que perde exatamente
-- as parcelas que a #87 acabou de publicar para não serem readivinhadas.
--
-- ⚠️ `competition` e `season` entram, e têm PROVENIÊNCIA DIFERENTE nos dois lados: o board
-- as tira das premissas, o funil do de-vig. Medido em 20/08, os dois concordam nos 391
-- fixtures — zero divergência —, então incluí-las não custa nada hoje e o dia em que elas
-- discordarem é um dia sobre o qual se quer saber (jogo cuja competição mudou entre a
-- coleta da odd e o registro do fixture).
--
-- Ficam de fora as colunas que só existem de um lado: `faixa`, `evidencias`, `avisos` e
-- `janela_deteccao` são do board (derivados ou de outra pergunta), `n_outcomes_valor`,
-- `janela_prioridade` e as oito portas são do funil.
--
-- ⚠️ AS QUATRO COLUNAS DE FLOAT ENTRAM ARREDONDADAS, e não por gosto. `avg_odd` é uma
-- média que o de-vig recalcula a cada leitura, e soma de FLOAT64 depende da ORDEM das
-- parcelas — ordem que o BigQuery não promete estável entre execuções. Medido em 21/08 na
-- validação da #96: o board trazia `1.7433333333333336` e o funil `1.7433333333333334`
-- para a MESMA linha. Duas linhas vermelhas, nenhum defeito, o 16º dígito. É o mesmo
-- knife-edge de float que a #92 já pagou uma vez.
--
-- A casa 10 é folgada de propósito: uma divergência de FÓRMULA — a coisa que esta guarda
-- existe para pegar — é ordens de grandeza maior que 1e-10, e nenhuma delas passaria por
-- aqui. O que passa é só o ruído de recomputação.
{%- set payload_float = ['edge', 'best_odd', 'avg_odd', 'prob_justa_fechamento'] %}
{%- set payload = [
    'pts_valor', 'pts_premissas', 'premissas_sem_dado', 'pts_corroboracao',
    'penalidades', 'penalidades_globais_pts', 'penalidades_especificas_pts',
    'pen_odd_outlier', 'pen_poucas_casas', 'pen_odd_longshot', 'pen_odd_juice',
    'modelo_api_concorda', 'linha_sharp_confirma',
    'best_book', 'n_casas',
    'valor_fonte', 'pin_n_outcomes', 'is_half_line', 'competition', 'season'
] %}

WITH fixtures AS (
    SELECT
        fixture_id,
        status_short AS _fx_status_short,
        kickoff_utc  AS _fx_kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

board AS (
    SELECT
        b.fixture_id,
        b.market,
        b.outcome,
        COALESCE(CAST(b.line_value AS STRING), 'NONE')  AS line_key,
        b.janela_usada                                  AS janela,
        b.score,
        {% for c in payload_float %}ROUND(b.{{ c }}, 10) AS {{ c }},
        {% endfor %}b.{{ payload | join(',\n        b.') }}
    FROM {{ ref('fact_value_opportunities') }} b
    -- o escopo do cabeçalho, escrito contra `fact_fixtures` porque o board não publica o
    -- kickoff. LEFT + COALESCE(..., TRUE): fixture ausente FICA, do mesmo jeito que fica
    -- do lado do funil.
    LEFT JOIN fixtures fx USING (fixture_id)
    WHERE {{ futebol_funil_e_gravavel('fx._fx_kickoff_utc') }}
),

-- O funil na leitura que o board faria: janela corrente, gate aprovado, e — só para a
-- direção 2 — sem os fixtures que o board expurga.
funil_publicavel AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        -- a coluna GRAVADA, não recomputada (ver a mesma nota na reconciliação).
        f.line_key,
        f.janela,
        f.score,
        {% for c in payload_float %}ROUND(f.{{ c }}, 10) AS {{ c }},
        {% endfor %}f.{{ payload | join(',\n        f.') }}
    FROM {{ ref('fact_value_funnel') }} f
    -- LEFT + COALESCE(..., FALSE): fixture ausente é fail-open aqui pelo mesmo motivo que
    -- é fail-open no board — a linha fica, e quem grita sobre fixture ausente é a
    -- assert_board_sem_jogo_encerrado, que tem diagnóstico próprio para isso.
    LEFT JOIN fixtures fx USING (fixture_id)
    WHERE f.janela_e_corrente
      AND f.passou_no_gate
      -- kickoff no futuro, ou desconhecido: o par comparável (ver o cabeçalho). Mesmo
      -- macro que congela o modelo, e — como do lado do board — lido de `fact_fixtures`,
      -- nunca da coluna da própria linha: a coluna congela no apito e os dois lados de um
      -- `EXCEPT` precisam do MESMO relógio.
      AND {{ futebol_funil_e_gravavel('fx._fx_kickoff_utc') }}
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
