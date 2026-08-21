





with validation_errors as (

    select
        player_id, stat_type
    from `smartbetting-dados`.`nba`.`dim_player_latest_line`
    group by player_id, stat_type
    having count(*) > 1

)

select *
from validation_errors


