





with validation_errors as (

    select
        fixture_id, event_order
    from `smartbetting-dados`.`futebol`.`fact_fixture_events`
    group by fixture_id, event_order
    having count(*) > 1

)

select *
from validation_errors


