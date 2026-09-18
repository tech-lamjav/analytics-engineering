





with validation_errors as (

    select
        fixture_id, dia_kickoff
    from `smartbetting-dados`.`futebol`.`fact_value_funnel_selo`
    group by fixture_id, dia_kickoff
    having count(*) > 1

)

select *
from validation_errors


