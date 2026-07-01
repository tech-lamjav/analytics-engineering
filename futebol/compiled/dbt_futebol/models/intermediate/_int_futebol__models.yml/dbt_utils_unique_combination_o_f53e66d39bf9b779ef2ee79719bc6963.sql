





with validation_errors as (

    select
        fixture_id, team_id, player_id
    from `smartbetting-dados`.`futebol`.`int_futebol_desfalques`
    group by fixture_id, team_id, player_id
    having count(*) > 1

)

select *
from validation_errors


