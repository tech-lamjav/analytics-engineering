
WITH most_recent_line_value AS (
    SELECT
        p.player_id,
        p.stat_type,
        p.line_value AS line_value_most_recent
    FROM `smartbetting-dados`.`nba`.`stg_player_props` p
    LEFT JOIN `smartbetting-dados`.`nba`.`stg_games` g
    ON g.game_id = p.game_id
    QUALIFY
        ROW_NUMBER()
            OVER (PARTITION BY p.player_id, p.stat_type ORDER BY g.game_date DESC)
    = 1
)
SELECT
    gps.player_id,
    gps.game_date,
    gps.game_id,
    gps.stat_type,
    gps.stat_value,
    o.line_value,
    mrlv.line_value_most_recent,
    gt.is_b2b_game,
    CASE
        WHEN o.line_value IS null THEN null
        WHEN gps.stat_value >= o.line_value THEN 'over'
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
    END AS is_played
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
LEFT JOIN
    most_recent_line_value AS mrlv
    ON gps.player_id = mrlv.player_id AND gps.stat_type = mrlv.stat_type
ORDER BY
    player_id,
    game_id