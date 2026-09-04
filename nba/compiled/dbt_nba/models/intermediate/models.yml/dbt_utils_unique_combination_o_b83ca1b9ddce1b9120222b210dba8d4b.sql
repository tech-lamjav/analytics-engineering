





with validation_errors as (

    select
        game_id, trigger_player_id
    from `smartbetting-dados`.`nba`.`int_daily_triggers`
    group by game_id, trigger_player_id
    having count(*) > 1

)

select *
from validation_errors


