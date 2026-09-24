

WITH src AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`raw_futebol_odds`
)

SELECT
    src.fixture_id,
    src.league_id,
    src.season,
    src.collection_window,
    src.collection_timestamp,
    TIMESTAMP_SECONDS(src.kickoff_timestamp) AS kickoff_utc,
    src.api_update,
    src.loaded_at,

    src.bookmaker_id,
    src.bookmaker_name,

    bet.id    AS market_id,
    bet.name  AS market_name,
    val.value AS outcome_label,
    SAFE_CAST(val.odd AS FLOAT64) AS odd_decimal
FROM src,
UNNEST(src.bets) AS bet,
UNNEST(bet.`values`) AS val  -- `values` é keyword SQL — crases
-- Defensivo: ignora eventual linha metadata-only (arquivo subido sem odds)
WHERE src.fixture_id IS NOT NULL