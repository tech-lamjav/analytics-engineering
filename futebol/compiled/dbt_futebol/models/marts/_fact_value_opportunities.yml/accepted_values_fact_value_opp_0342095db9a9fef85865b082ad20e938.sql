
    
    

with all_values as (

    select
        valor_fonte as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_opportunities`
    group by valor_fonte

)

select *
from all_values
where value_field not in (
    'pinnacle','consenso'
)


