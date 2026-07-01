





with validation_errors as (

    select
        player_id, game_id, stat_type
    from `smartbetting-dados`.`nba`.`ft_game_player_stats`
    group by player_id, game_id, stat_type
    having count(*) > 1

)

select *
from validation_errors


