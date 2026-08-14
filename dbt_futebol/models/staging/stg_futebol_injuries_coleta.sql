{#- ⚠️ TABLE, e não a view padrão do staging — é decisão de CUSTO, não de estilo.

    A fonte é NDJSON externo, sem predicate pushdown: qualquer leitura varre o prefixo inteiro
    (236 MiB em 2026-08-14, e ele acumula 1 arquivo por fixture por dia). Como view, cada
    rebuild do int_futebol_premissas_1x2 pagaria essa varredura — e quem o reconstrói é o
    `futebol-odds-pregame`, de 15 em 15 minutos, 96× por dia. São ~22 GB/dia de varredura para
    responder a uma pergunta que só muda de hora em hora, porque o poll de /injuries roda de
    hora em hora: a tabela não pode ser mais fresca que a fonte dela.

    Então ela é construída onde a varredura JÁ acontece — junto do fact_injuries_snapshot, nos
    workflows diário e de injuries (horário) — e o caminho de 15 minutos lê tabela nativa. O
    `dbt_utils.recency` no yml é o que pega o modo de falha desta escolha: tabela que parou de
    ser reconstruída envelhece em silêncio, e jogo recente passa a parecer nunca perguntado.

    ⚠️ Isto exige que o modelo esteja nos `--select` dos dois workflows (data-engineering):
    sem isso ele nunca é reconstruído em produção, e editar este arquivo não muda nada lá. -#}
{{ config(
    materialized='table',
    description='O REGISTRO DE QUE PERGUNTAMOS (#42, ADR 0003) — 1 linha por (fixture, dia de coleta) do poll pré-jogo de /injuries?fixture, INCLUSIVE quando a fonte não devolveu desfalque nenhum. É o único lugar onde o VAZIO REGISTRADO (data-engineering#33) sobrevive: o stg_futebol_injuries o descarta por desenho (player.id IS NOT NULL, com not_null em cima), porque vazio não é desfalque — mas é resposta, e sem ela "perguntamos e a fonte não tinha" e "nunca perguntamos" são o mesmo estado. Consumido por int_futebol_premissas_1x2, que só pode deixar s_missing/o_missing valerem ZERO onde existe registro; sem registro o contador é NULL. ⚠️ O discriminador é o NOME DO ARQUIVO: o poll por fixture grava raw_futebol_injuries_{fixture}_{janela}_{dia}.json e o season-log grava raw_futebol_injuries_{current|backfill}_{dia}.json — o segmento após o endpoint é numérico só no primeiro. Casar o número, e não a janela, porque a janela é configuração (FUTEBOL_INJURIES_WINDOWS, hoje só `daily`) e renomeá-la não deve apagar o registro em silêncio.'
) }}

WITH src AS (
    SELECT
        _FILE_NAME AS arquivo,
        fixture.id AS fixture_id,
        snapshot_date,
        loaded_at
    FROM {{ source('futebol', 'raw_futebol_injuries') }}
)

SELECT
    fixture_id,
    snapshot_date,
    -- Instante da coleta. É ele — e não o snapshot_date — que decide se a resposta é
    -- pré-apito: o poll roda de hora em hora e no dia do jogo há coleta antes E depois do
    -- apito (mesma razão pela qual int_futebol_desfalques usa extracted_at).
    MIN(loaded_at) AS coletado_em
FROM src
WHERE fixture_id IS NOT NULL
  -- Só o poll POR FIXTURE registra o vazio; o season-log é por (liga, season) e a ausência
  -- de um jogo nele não é resposta sobre aquele jogo.
  AND REGEXP_CONTAINS(arquivo, r'/raw_futebol_injuries_[0-9]+_')
GROUP BY fixture_id, snapshot_date
