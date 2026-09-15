





with validation_errors as (

    select
        game_id, trigger_player_id, backup_player_id, stat_type
    from `smartbetting-dados`.`nba`.`dim_daily_opportunities`
    group by game_id, trigger_player_id, backup_player_id, stat_type
    having count(*) > 1

)

select *
from validation_errors


