





with validation_errors as (

    select
        player_id, game_id, period
    from `smartbetting-dados`.`nba`.`stg_game_player_advanced_stats`
    group by player_id, game_id, period
    having count(*) > 1

)

select *
from validation_errors


