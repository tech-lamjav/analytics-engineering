
    
    

with all_values as (

    select
        origem as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_funnel`
    group by origem

)

select *
from all_values
where value_field not in (
    'backfill','corrente'
)


