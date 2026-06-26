{{ config(
    description='Game-level spread and total O/U from raw_betting_odds. One row per game, preferred vendor (draftkings > fanduel > others).'
) }}

SELECT
    CAST(game_id AS INT64)              AS game_id,
    CAST(season  AS INT64)              AS season,
    vendor,
    CAST(spread_home_value AS FLOAT64)  AS spread,
    CAST(spread_away_value AS FLOAT64)  AS spread_away,
    CAST(total_value       AS FLOAT64)  AS total,
    CAST(spread_home_odds  AS INT64)    AS spread_home_odds,
    CAST(spread_away_odds  AS INT64)    AS spread_away_odds,
    CAST(total_over_odds   AS INT64)    AS total_over_odds,
    CAST(total_under_odds  AS INT64)    AS total_under_odds,
    CAST(moneyline_home_odds AS INT64)  AS moneyline_home_odds,
    CAST(moneyline_away_odds AS INT64)  AS moneyline_away_odds,
    CAST(updated_at AS TIMESTAMP)       AS updated_at
FROM {{ source('nba', 'raw_betting_odds') }}
WHERE spread_home_value IS NOT NULL
   OR total_value IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY game_id
    -- Desempate determinístico: vendor preferido -> snapshot mais recente -> id estável.
    -- (sem isso, vendors fora de DK/FanDuel empatam em prioridade 3 e a linha é arbitrária.)
    ORDER BY
        CASE vendor WHEN 'draftkings' THEN 1 WHEN 'fanduel' THEN 2 ELSE 3 END,
        CAST(updated_at AS TIMESTAMP) DESC,
        id
) = 1
