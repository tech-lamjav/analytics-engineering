





with validation_errors as (

    select
        player_id, stat_type
    from `smartbetting-dados`.`nba`.`int_season_averages_general_base`
    group by player_id, stat_type
    having count(*) > 1

)

select *
from validation_errors


