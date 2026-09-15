





with validation_errors as (

    select
        fixture_id, snapshot_date
    from `smartbetting-dados`.`futebol`.`stg_futebol_injuries_coleta`
    group by fixture_id, snapshot_date
    having count(*) > 1

)

select *
from validation_errors


