





with validation_errors as (

    select
        fixture_id, loaded_at
    from `smartbetting-dados`.`futebol`.`stg_futebol_fixtures`
    group by fixture_id, loaded_at
    having count(*) > 1

)

select *
from validation_errors


