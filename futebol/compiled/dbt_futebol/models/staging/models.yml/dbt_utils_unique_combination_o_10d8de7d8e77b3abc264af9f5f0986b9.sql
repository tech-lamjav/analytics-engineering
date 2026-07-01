





with validation_errors as (

    select
        player_id, requested_league_id, requested_season
    from `smartbetting-dados`.`futebol`.`stg_futebol_players`
    group by player_id, requested_league_id, requested_season
    having count(*) > 1

)

select *
from validation_errors


