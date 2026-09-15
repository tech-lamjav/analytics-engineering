





with validation_errors as (

    select
        fixture_id, outcome
    from `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
    group by fixture_id, outcome
    having count(*) > 1

)

select *
from validation_errors


