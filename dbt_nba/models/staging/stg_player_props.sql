{{ config(
    description='Staging table for NBA player props from DraftKings NDJSON external table'
) }}

WITH source_data AS (
    SELECT * FROM {{ source('nba', 'raw_player_props') }}
),

cleaned_data AS (
    SELECT
        id AS prop_id,
        player_id,
        game_id,
        season,
        vendor,
        --prop_type,
        -- Normalize prop_type to match stat_type format (with 'player_' prefix)
        CASE
            WHEN prop_type = 'assists' THEN 'player_assists'
            WHEN prop_type = 'assists_1q' THEN 'player_assists_1q'
            WHEN prop_type = 'assists_first3min' THEN 'player_assists_first3min'
            WHEN prop_type = 'blocks' THEN 'player_blocks'
            WHEN prop_type = 'double_double' THEN 'player_double_double'
            WHEN prop_type = 'points' THEN 'player_points'
            WHEN prop_type = 'points_1q' THEN 'player_points_1q'
            WHEN prop_type = 'points_assists' THEN 'player_points_assists'
            WHEN prop_type = 'points_first3min' THEN 'player_points_first3min'
            WHEN prop_type = 'points_rebounds' THEN 'player_points_rebounds'
            WHEN prop_type = 'points_rebounds_assists' THEN 'player_points_rebounds_assists'
            WHEN prop_type = 'rebounds' THEN 'player_rebounds'
            WHEN prop_type = 'rebounds_1q' THEN 'player_rebounds_1q'
            WHEN prop_type = 'rebounds_assists' THEN 'player_rebounds_assists'
            WHEN prop_type = 'rebounds_first3min' THEN 'player_rebounds_first3min'
            WHEN prop_type = 'steals' THEN 'player_steals'
            WHEN prop_type = 'threes' THEN 'player_threes'
            WHEN prop_type = 'triple_double' THEN 'player_triple_double'
            ELSE 'player_' || prop_type  -- Fallback: add prefix if not in mapping
        END AS stat_type,
        CAST(line_value AS FLOAT64) AS line_value,
        --(CAST(market.odds AS FLOAT64) / 100) + 1 AS market_odds,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source_data
    WHERE market.type = 'over_under'
)

SELECT * FROM cleaned_data
