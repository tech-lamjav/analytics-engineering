





with validation_errors as (

    select
        fixture_id, market, outcome, line_value
    from `smartbetting-dados`.`futebol`.`fact_value_opportunities`
    group by fixture_id, market, outcome, line_value
    having count(*) > 1

)

select *
from validation_errors


