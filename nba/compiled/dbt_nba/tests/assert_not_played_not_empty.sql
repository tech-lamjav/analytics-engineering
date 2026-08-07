-- Falha se int_game_player_stats_not_played voltar a ficar permanentemente vazio.
-- Protege contra a regressão em que o filtro minutes > 0 na staging zerava a
-- detecção de DNP (e quebrava silenciosamente dim_stat_player / ft_game_player_stats).
SELECT 1
FROM (
    SELECT COUNT(*) AS n
    FROM `smartbetting-dados`.`nba`.`int_game_player_stats_not_played`
)
WHERE n = 0