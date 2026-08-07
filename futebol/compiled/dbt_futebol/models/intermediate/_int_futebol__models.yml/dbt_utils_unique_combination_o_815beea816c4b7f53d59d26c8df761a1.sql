





with validation_errors as (

    select
        fixture_id, market_id, outcome_side, line_value
    from `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    group by fixture_id, market_id, outcome_side, line_value
    having count(*) > 1

)

select *
from validation_errors


