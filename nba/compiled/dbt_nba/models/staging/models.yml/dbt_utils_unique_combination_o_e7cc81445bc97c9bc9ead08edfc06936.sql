





with validation_errors as (

    select
        player_id, game_id
    from `smartbetting-dados`.`nba`.`stg_game_player_stats_all`
    group by player_id, game_id
    having count(*) > 1

)

select *
from validation_errors


