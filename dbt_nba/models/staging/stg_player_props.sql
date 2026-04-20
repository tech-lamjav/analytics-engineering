{{ config(
    description='Staging table for NBA player props — union of DraftKings, Caesars, BetRivers. Deduped to 1 row per player/game/prop_type (caesars > betrivers > draftkings priority).'
) }}

WITH all_vendors AS (
    SELECT id, player_id, game_id, season, vendor, prop_type, line_value, market.type AS market_type
    FROM {{ source('nba', 'raw_player_props') }}
    UNION ALL
    SELECT id, player_id, game_id, season, vendor, prop_type, line_value, market.type AS market_type
    FROM {{ source('nba', 'raw_player_props_caesars') }}
    UNION ALL
    SELECT id, player_id, game_id, season, vendor, prop_type, line_value, market.type AS market_type
    FROM {{ source('nba', 'raw_player_props_betrivers') }}
),

cleaned_data AS (
    SELECT
        id AS prop_id,
        player_id,
        game_id,
        season,
        vendor,
        CASE
            WHEN prop_type = 'assists'                   THEN 'player_assists'
            WHEN prop_type = 'assists_1q'                THEN 'player_assists_1q'
            WHEN prop_type = 'assists_first3min'         THEN 'player_assists_first3min'
            WHEN prop_type = 'blocks'                    THEN 'player_blocks'
            WHEN prop_type = 'double_double'             THEN 'player_double_double'
            WHEN prop_type = 'points'                    THEN 'player_points'
            WHEN prop_type = 'points_1q'                 THEN 'player_points_1q'
            WHEN prop_type = 'points_assists'            THEN 'player_points_assists'
            WHEN prop_type = 'points_first3min'          THEN 'player_points_first3min'
            WHEN prop_type = 'points_rebounds'           THEN 'player_points_rebounds'
            WHEN prop_type = 'points_rebounds_assists'   THEN 'player_points_rebounds_assists'
            WHEN prop_type = 'rebounds'                  THEN 'player_rebounds'
            WHEN prop_type = 'rebounds_1q'               THEN 'player_rebounds_1q'
            WHEN prop_type = 'rebounds_assists'          THEN 'player_rebounds_assists'
            WHEN prop_type = 'rebounds_first3min'        THEN 'player_rebounds_first3min'
            WHEN prop_type = 'steals'                    THEN 'player_steals'
            WHEN prop_type = 'threes'                    THEN 'player_threes'
            WHEN prop_type = 'triple_double'             THEN 'player_triple_double'
            ELSE 'player_' || prop_type
        END AS stat_type,
        CAST(line_value AS FLOAT64) AS line_value
    FROM all_vendors
    WHERE market_type = 'over_under'
    -- 1 row per player/game/prop_type to prevent fan-out in ft_game_player_stats JOIN.
    -- Priority per stat (based on volume analysis in docs/analise_player_props.md §2c):
    --   individual stats → draftkings | points_rebounds_assists → betrivers | combos P+R/P+A/R+A → caesars
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY player_id, game_id, prop_type
        ORDER BY CASE
            WHEN prop_type IN ('points', 'rebounds', 'assists', 'threes', 'steals', 'blocks')
                THEN CASE vendor WHEN 'draftkings' THEN 1 WHEN 'caesars' THEN 2 ELSE 3 END
            WHEN prop_type = 'points_rebounds_assists'
                THEN CASE vendor WHEN 'betrivers' THEN 1 WHEN 'caesars' THEN 2 ELSE 3 END
            WHEN prop_type IN ('points_rebounds', 'points_assists', 'rebounds_assists')
                THEN CASE vendor WHEN 'caesars' THEN 1 WHEN 'betrivers' THEN 2 ELSE 3 END
            ELSE CASE vendor WHEN 'caesars' THEN 1 WHEN 'betrivers' THEN 2 ELSE 3 END
        END
    ) = 1
)

SELECT * FROM cleaned_data
