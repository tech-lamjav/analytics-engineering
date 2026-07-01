

WITH ps AS (
    SELECT
        player_id,
        competition_id,
        fixture_id,
        is_substitute,
        minutes,
        rating
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_player_stats`
),

agg AS (
    SELECT
        player_id,
        competition_id,
        COUNT(DISTINCT fixture_id)       AS games,
        COUNTIF(is_substitute = FALSE)   AS starts,   -- is_substitute=FALSE => começou jogando
        SUM(minutes)                     AS total_minutes,
        AVG(rating)                      AS avg_rating
    FROM ps
    GROUP BY player_id, competition_id
)

SELECT
    player_id,
    competition_id,
    games,
    starts,
    SAFE_DIVIDE(starts, games)         AS start_share,
    total_minutes,
    SAFE_DIVIDE(total_minutes, games)  AS avg_minutes,
    avg_rating,
    -- titular regular: minutos suficientes E começa a maioria das aparições.
    COALESCE(total_minutes >= 450 AND SAFE_DIVIDE(starts, games) >= 0.5, FALSE) AS is_important,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM agg