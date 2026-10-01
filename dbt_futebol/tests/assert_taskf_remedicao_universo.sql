{{ config(tags=['taskf']) }}
-- GUARDA DA REMEDIÇÃO NA JANELA NOVA (AE#117, ADR 0010 termo 5) — a contraparte, para o destino
-- `remedicao`, do que a Costura B é para o 2×2.
--
-- A Costura B NÃO enxerga estas tabelas: ela cobra `taskf_universos()` × quatro células da
-- acumulativa congelada, e é por isso que os universos da janela nova moram numa lista à parte
-- (macros/taskf_universos.sql). Sem uma guarda aqui, a remedição seria a única medição da [F] sem
-- ninguém conferindo que ela mediu o universo declarado — e o termo 5 da ADR é exatamente "o Teste
-- 2 rodou NESSA janela".
--
-- LÊ SÓ `source()`, pelo mesmo motivo da Costura B (não pendurar a guarda no grafo dos modelos).
-- NÃO é agendada: tag `taskf`, nunca `guarda`, e fala de um dataset que produção não lê. Roda
-- depois da medição, com `dbt test --target taskF --select assert_taskf_remedicao_universo`.
--
-- O QUE É COBRADO, em quatro blocos:
--
--   presenca             cada leitura (sem gate / com gate) tem a célula default (`ambos`) em CADA
--                        universo de taskf_universos_janela_nova(). Também é a não-vacuidade: uma
--                        medição interrompida deixaria tabela vazia, e o resto passaria em branco.
--   universo_fora_do_gabarito
--                        os jogos do universo primário são os que a contagem final de 01/10
--                        declarou, POR LEITURA (taskf_janela_nova().jogos_esperados). É o que pega
--                        medir o universo errado — fatos do taskF defasados de produção, uma
--                        seleção que entrou, um filtro de status que mudou.
--   janela_fora_dos_limites
--                        o primeiro e o último dia de kickoff medido cabem em
--                        [DATE(ini), DATE(fim) - 1 dia]. O fim é exclusivo e 00:00:00, então o
--                        último dia possível é 30/09.
--   execucao_divergente  as duas leituras saíram do MESMO commit (com procedência declarada) e leram
--                        a MESMA construção dos fatos, ANTES de medir. Uma leitura com gate de
--                        outro commit não seria "ao lado" da primária, seria outra medição.
--
-- ⚠️ O gabarito é um VALOR FIXO porque a janela está FECHADA. Diferente dos universos estendidos do
-- 2×2, não há crescimento legítimo a cada construção dos fatos; um número diferente é fato que
-- andou (resultado que entrou tarde, jogo remarcado) e tem de ser lido, não absorvido.

{% set w = taskf_janela_nova() %}
{% set universos = taskf_universos_janela_nova() %}
{% set celula = taskf_celula().nome %}
{% set leituras = [
    {'chave': 'sem_gate', 'tabela': 'taskf_teste2_remedicao'},
    {'chave': 'com_gate', 'tabela': 'taskf_teste2_remedicao_com_gate'}
] %}

WITH celulas AS (
    {%- for l in leituras %}
    SELECT
        '{{ l.chave }}'                AS leitura,
        universo,
        celula,
        ANY_VALUE(jogos_no_universo)   AS jogos_no_universo,
        ANY_VALUE(janela_ini)          AS janela_ini,
        ANY_VALUE(janela_fim)          AS janela_fim,
        ANY_VALUE(odds_loaded_at)      AS odds_loaded_at,
        ANY_VALUE(git_sha)             AS git_sha,
        MIN(medido_em)                 AS medido_em,
        -- Constantes por construção dentro de uma célula; COUNT(DISTINCT) confere em vez de supor
        -- (TO_JSON_STRING e não FORMAT: FORMAT devolve NULL com um argumento NULL e a linha sairia
        -- do COUNT) — mesmo argumento e mesma forma da Costura B.
        COUNT(DISTINCT TO_JSON_STRING(STRUCT(
            jogos_no_universo, janela_ini, janela_fim, odds_loaded_at, git_sha))) AS versoes_na_celula
    FROM {{ source('futebol_taskF', l.tabela) }}
    GROUP BY universo, celula
    {{ 'UNION ALL' if not loop.last }}
    {%- endfor %}
),

esperadas AS (
    SELECT leitura, universo
    FROM UNNEST(['sem_gate', 'com_gate']) AS leitura
    CROSS JOIN UNNEST({{ universos | map(attribute='nome') | list | tojson }}) AS universo
),

presenca AS (
    SELECT
        'celula_faltando_ou_sobrando' AS motivo,
        TO_JSON_STRING(STRUCT(
            e.leitura AS leitura_esperada, e.universo AS universo_esperado,
            c.leitura AS leitura_encontrada, c.universo AS universo_encontrado,
            c.celula AS celula_encontrada, '{{ celula }}' AS celula_esperada
        )) AS linha
    FROM esperadas AS e
    FULL OUTER JOIN celulas AS c
      ON c.leitura = e.leitura AND c.universo = e.universo
    WHERE e.universo IS NULL OR c.universo IS NULL OR c.celula <> '{{ celula }}'
),

gabarito AS (
    SELECT
        'universo_fora_do_gabarito' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.leitura, c.universo, c.jogos_no_universo, g.jogos_esperados
        )) AS linha
    FROM celulas AS c
    JOIN (
        SELECT 'sem_gate' AS leitura, {{ w.jogos_esperados.sem_gate }} AS jogos_esperados
        UNION ALL
        SELECT 'com_gate', {{ w.jogos_esperados.com_gate }}
    ) AS g ON g.leitura = c.leitura
    WHERE c.universo = 'janela_nova'
      AND c.jogos_no_universo IS DISTINCT FROM g.jogos_esperados
),

janela AS (
    SELECT
        'janela_fora_dos_limites' AS motivo,
        TO_JSON_STRING(STRUCT(
            leitura, universo, janela_ini, janela_fim,
            DATE('{{ w.ini }}')                            AS limite_inferior,
            DATE_SUB(DATE('{{ w.fim }}'), INTERVAL 1 DAY)  AS limite_superior
        )) AS linha
    FROM celulas
    WHERE janela_ini IS NULL OR janela_fim IS NULL
       OR janela_ini < DATE('{{ w.ini }}')
       OR janela_fim > DATE_SUB(DATE('{{ w.fim }}'), INTERVAL 1 DAY)
),

referencia AS (
    SELECT * FROM celulas ORDER BY leitura, universo LIMIT 1
),

execucao AS (
    SELECT
        'execucao_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.leitura, c.universo,
            c.odds_loaded_at, r.odds_loaded_at AS odds_loaded_at_ref,
            c.medido_em, c.git_sha, r.git_sha AS git_sha_ref,
            c.versoes_na_celula
        )) AS linha
    FROM celulas AS c
    CROSS JOIN referencia AS r
    WHERE c.odds_loaded_at IS DISTINCT FROM r.odds_loaded_at
       OR c.odds_loaded_at IS NULL
       OR NOT (c.odds_loaded_at < c.medido_em)
       OR c.git_sha IS DISTINCT FROM r.git_sha
       OR c.git_sha = 'desconhecido'
       OR c.git_sha IS NULL
       OR c.versoes_na_celula <> 1
)

SELECT motivo, linha FROM presenca
UNION ALL
SELECT motivo, linha FROM gabarito
UNION ALL
SELECT motivo, linha FROM janela
UNION ALL
SELECT motivo, linha FROM execucao
