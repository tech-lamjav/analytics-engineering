





with validation_errors as (

    select
        player_id, game_id
    from `smartbetting-dados`.`nba`.`int_game_player_stats_not_played`
    group by player_id, game_id
    having count(*) > 1

)

select *
from validation_errors


