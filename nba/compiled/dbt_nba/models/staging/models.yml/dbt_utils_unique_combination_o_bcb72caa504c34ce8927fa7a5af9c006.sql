





with validation_errors as (

    select
        player_id, game_id, stat_type
    from `smartbetting-dados`.`nba`.`stg_player_props`
    group by player_id, game_id, stat_type
    having count(*) > 1

)

select *
from validation_errors


