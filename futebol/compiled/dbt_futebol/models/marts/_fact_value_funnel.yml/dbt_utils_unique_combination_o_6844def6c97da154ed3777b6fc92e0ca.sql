





with validation_errors as (

    select
        fixture_id, market, outcome, line_key, janela
    from `smartbetting-dados`.`futebol`.`fact_value_funnel`
    group by fixture_id, market, outcome, line_key, janela
    having count(*) > 1

)

select *
from validation_errors


