





with validation_errors as (

    select
        fixture_id, line_value, outcome
    from `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
    group by fixture_id, line_value, outcome
    having count(*) > 1

)

select *
from validation_errors


