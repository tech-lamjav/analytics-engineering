





with validation_errors as (

    select
        fixture_id, team_id
    from `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`
    group by fixture_id, team_id
    having count(*) > 1

)

select *
from validation_errors


