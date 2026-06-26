{{ config(
    description='Intermediate model that gets the games where players did not play (DNP: minutes = 0 ou NULL); lê de stg_game_player_stats_all (sem o filtro minutes > 0)'
) }}

WITH

injury_games AS (
    SELECT DISTINCT
        player_id,
        team_id,
        game_id
    -- Lê da staging SEM o filtro minutes > 0; senão nenhuma linha de DNP
    -- sobrevive e o modelo fica permanentemente vazio (regressão crítica).
    FROM {{ ref('stg_game_player_stats_all') }}
    WHERE NOT did_play  -- minutes = 0 OU minutes IS NULL
)

SELECT * FROM injury_games