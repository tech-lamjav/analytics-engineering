
SELECT
    gps.player_id,
    gps.game_date,
    gps.game_id,
    gps.stat_type,
    gps.stat_value,
    o.line_value,
    gt.is_b2b_game,
    CASE
        WHEN o.line_value IS null THEN null
        WHEN gps.stat_value = o.line_value THEN 'push'   -- empate exato (so ocorre em linha inteira): aposta devolvida, nao e 'over'
        WHEN gps.stat_value > o.line_value THEN 'over'
        WHEN gps.stat_value < o.line_value THEN 'under'
    END AS stat_vs_line,
    CASE
        WHEN gps.team_id = gt.home_team_id THEN gt.visitor_team_abbreviation
        WHEN gps.team_id = gt.visitor_team_id THEN '@' || gt.home_team_abbreviation
    END AS played_against,
    CASE
        WHEN gps.team_id = gt.home_team_id THEN 'Casa'
        WHEN gps.team_id = gt.visitor_team_id THEN 'Fora'
    END AS home_away,
    CASE
        WHEN not_played.player_id IS NOT null THEN 'Não jogou'
        ELSE 'Jogou'
    END AS is_played,
    CURRENT_TIMESTAMP() AS loaded_at
FROM
    `smartbetting-dados`.`nba`.`int_game_player_stats_pilled` AS gps
LEFT JOIN
    `smartbetting-dados`.`nba`.`int_games_teams_pilled` AS gt
    ON gps.game_id = gt.game_id AND gps.team_id = gt.team_id AND gt.game_date <= CURRENT_DATE()
LEFT JOIN `smartbetting-dados`.`nba`.`stg_player_props` AS o ON gps.player_id = o.player_id
    AND gps.game_id = o.game_id
    AND o.stat_type = gps.stat_type
LEFT JOIN
    `smartbetting-dados`.`nba`.`int_game_player_stats_not_played` AS not_played
    ON gps.player_id = not_played.player_id AND gps.game_id = not_played.game_id AND gps.team_id = not_played.team_id
WHERE gps.season = 2025

  AND gps.game_date >= DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 3 DAY)
