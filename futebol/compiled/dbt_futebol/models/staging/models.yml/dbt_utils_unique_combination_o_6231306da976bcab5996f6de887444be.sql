





with validation_errors as (

    select
        fixture_id, team_id
    from `smartbetting-dados`.`futebol`.`stg_futebol_fixture_statistics`
    group by fixture_id, team_id
    having count(*) > 1

)

select *
from validation_errors


