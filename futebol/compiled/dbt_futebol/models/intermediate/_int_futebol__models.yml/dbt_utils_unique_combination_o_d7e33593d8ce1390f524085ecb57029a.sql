





with validation_errors as (

    select
        player_id, competition_id
    from `smartbetting-dados`.`futebol`.`int_futebol_player_importance`
    group by player_id, competition_id
    having count(*) > 1

)

select *
from validation_errors


