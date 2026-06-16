{{ config(
    description='Flatten do raw_futebol_odds. 1 linha por (fixture, janela, casa, mercado, outcome) — UNNEST 2× (bets → values; `values` é keyword SQL, escapado com crases). odd STRING → odd_decimal FLOAT64 (SAFE_CAST); kickoff_timestamp unix → kickoff_utc TIMESTAMP. Mantém TODOS os mercados e casas — o afunilamento p/ os 8 mercados-alvo acontece em fact_odds_snapshot. A linha do outcome (value) já embute a linha do mercado (ex.: "Over 2.5", "Home -0.5", "0:0"), então (mercado, outcome) é único por (fixture, casa, janela). Filtro defensivo contra linha metadata-only.'
) }}

WITH src AS (
    SELECT * FROM {{ source('futebol', 'raw_futebol_odds') }}
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
