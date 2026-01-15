{{ config(
    description='Intermediate model that gets the last game text for each player'
) }}

WITH last_games_text AS (
    SELECT
        player_id,
        MAX(game_date) AS last_game_date
    FROM
        {{ ref('stg_game_player_stats') }}
    WHERE
        minutes > 0
    GROUP BY
        player_id
),

last_game_text AS (
    SELECT
        player_id,
        CONCAT(
            'Ultimo Jogo: ',
            CAST(DATE_DIFF(CURRENT_DATE(), last_game_date, DAY) AS STRING),
            ' ',
            CASE
                WHEN DATE_DIFF(CURRENT_DATE(), last_game_date, DAY) = 1 THEN 'dia atras'
                ELSE 'dias atras'
            END
        ) AS last_game_text,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM
        last_games_text
)

SELECT * FROM last_game_text