





with validation_errors as (

    select
        fixture_id
    from `smartbetting-dados`.`futebol`.`fact_predictions_api`
    group by fixture_id
    having count(*) > 1

)

select *
from validation_errors


