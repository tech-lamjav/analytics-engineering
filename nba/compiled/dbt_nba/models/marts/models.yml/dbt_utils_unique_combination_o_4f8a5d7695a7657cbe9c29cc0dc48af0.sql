





with validation_errors as (

    select
        trigger_player_id, teammate_player_id, stat_type
    from `smartbetting-dados`.`nba`.`dim_teammate_impact_360`
    group by trigger_player_id, teammate_player_id, stat_type
    having count(*) > 1

)

select *
from validation_errors


