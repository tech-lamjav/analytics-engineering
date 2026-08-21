

WITH src AS (
    SELECT
        _FILE_NAME AS arquivo,
        fixture.id AS fixture_id,
        snapshot_date,
        loaded_at
    FROM `smartbetting-dados`.`futebol`.`raw_futebol_injuries`
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