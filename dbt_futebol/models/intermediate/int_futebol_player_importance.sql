{{ config(
    materialized='view',
    description='S7 do Motor de Score — proxy de IMPORTÂNCIA de jogador (minutos x titularidade) p/ pesar desfalques no 1X2. 1 linha por (player_id, competition_id), POOLING todas as seasons (2024/25/26) — importância é atributo ESTÁVEL do jogador, não métrica point-in-time; pooling dá amostra robusta mesmo com 2026 ralo na pausa FIFA. Fonte: fact_fixture_player_stats (só jogos FT). is_important = titular regular: total_minutes >= 450 (~5 jogos cheios, filtra cameos) E start_share >= 0.5 (começa metade das aparições). Degradação graciosa: jogador sem stats (contratação nova / Copa) não entra aqui -> is_important = FALSE no consumidor. ⚠️ Look-ahead: p/ jogos FUTUROS não há (todo player_stat é passado); em validação de jogo HISTÓRICO o pool inclui jogos posteriores ao fixture (aceitável p/ atributo estável). Thresholds = ponto de partida, tunáveis (§13).'
) }}

WITH ps AS (
    SELECT
        player_id,
        competition_id,
        fixture_id,
        is_substitute,
        minutes,
        rating
    FROM {{ ref('fact_fixture_player_stats') }}
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
