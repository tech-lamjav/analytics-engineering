

WITH source_data AS (
    SELECT * FROM `smartbetting-dados`.`nba`.`raw_game_player_stats`
    WHERE season = 2025
),

unnested AS (
    SELECT
        season,
        stat
    FROM source_data,
    UNNEST(stats) AS stat
),

cleaned_data AS (
    SELECT
        stat.player.id AS player_id,
        stat.team.id   AS team_id,
        stat.game.id   AS game_id,
        SAFE_CAST(stat.game.date AS DATE) AS game_date,
        season,
        -- minutes anulável: SAFE_CAST evita erro de runtime em min nulo/não numérico (linhas DNP).
        SAFE_CAST(stat.min AS INTEGER) AS minutes,
        -- did_play = jogou de fato (minutos presentes e > 0); linhas DNP => FALSE.
        (SAFE_CAST(stat.min AS INTEGER) IS NOT NULL AND SAFE_CAST(stat.min AS INTEGER) > 0) AS did_play
    FROM unnested
    -- NOTA: SEM filtro de minutos aqui (de propósito). As linhas com min nulo/0 são exatamente
    -- as que int_game_player_stats_not_played precisa para detectar quem NÃO jogou.
)

SELECT * FROM cleaned_data