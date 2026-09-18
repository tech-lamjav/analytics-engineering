
    
    

with all_values as (

    select
        janela as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_funnel`
    group by janela

)

select *
from all_values
where value_field not in (
    'daily','t24h','t1h','t15m'
)


