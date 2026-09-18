





with validation_errors as (

    select
        fixture_id, outcome, market, line_value, premissa, insumo
    from `smartbetting-dados`.`futebol`.`fact_insumos_medidos`
    group by fixture_id, outcome, market, line_value, premissa, insumo
    having count(*) > 1

)

select *
from validation_errors


