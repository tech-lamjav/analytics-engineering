{{ config(
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
