

WITH all_vendors AS (
    SELECT id, player_id, game_id, season, vendor, prop_type, line_value, market.type AS market_type
    FROM `smartbetting-dados`.`nba`.`raw_player_props`
    UNION ALL
    SELECT id, player_id, game_id, season, vendor, prop_type, line_value, market.type AS market_type
    FROM `smartbetting-dados`.`nba`.`raw_player_props_caesars`
    UNION ALL
    SELECT id, player_id, game_id, season, vendor, prop_type, line_value, market.type AS market_type
    FROM `smartbetting-dados`.`nba`.`raw_player_props_betrivers`
),

cleaned_data AS (
    SELECT
        id AS prop_id,
        player_id,
        game_id,
        season,
        vendor,
        prop_type,
        -- Todo branch do CASE antigo era 'player_' || prop_type (o ELSE já cobria tudo).
        'player_' || prop_type AS stat_type,
        CAST(line_value AS FLOAT64) AS line_value
    FROM all_vendors
    WHERE market_type = 'over_under'
),

-- Mediana da linha por (player, game, prop, vendor) como proxy da "linha principal".
-- Necessária porque props de linha alternada (PRA e combos P+R/P+A/R+A) trazem várias
-- linhas no mesmo vendor com o MESMO updated_at, então recência não desempata.
with_line_median AS (
    SELECT
        *,
        PERCENTILE_CONT(line_value, 0.5) OVER (
            PARTITION BY player_id, game_id, prop_type, vendor
        ) AS line_value_median
    FROM cleaned_data
),

deduped AS (
    SELECT
        prop_id,
        player_id,
        game_id,
        season,
        vendor,
        stat_type,
        line_value
    FROM with_line_median
    -- 1 row per player/game/prop_type to prevent fan-out in ft_game_player_stats JOIN.
    -- Priority per stat (based on volume analysis in docs/analise_player_props.md §2c):
    --   individual stats → draftkings | points_rebounds_assists → betrivers | combos P+R/P+A/R+A → caesars
    -- Desempate determinístico: vendor prioritário → linha mais próxima da mediana (linha principal) → menor linha.
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY player_id, game_id, prop_type
        ORDER BY
            CASE
                WHEN prop_type IN ('points', 'rebounds', 'assists', 'threes', 'steals', 'blocks')
                    THEN CASE vendor WHEN 'draftkings' THEN 1 WHEN 'caesars' THEN 2 ELSE 3 END
                WHEN prop_type = 'points_rebounds_assists'
                    THEN CASE vendor WHEN 'betrivers' THEN 1 WHEN 'caesars' THEN 2 ELSE 3 END
                WHEN prop_type IN ('points_rebounds', 'points_assists', 'rebounds_assists')
                    THEN CASE vendor WHEN 'caesars' THEN 1 WHEN 'betrivers' THEN 2 ELSE 3 END
                ELSE CASE vendor WHEN 'caesars' THEN 1 WHEN 'betrivers' THEN 2 ELSE 3 END
            END,
            ABS(line_value - line_value_median) ASC,
            line_value ASC
    ) = 1
)

SELECT * FROM deduped