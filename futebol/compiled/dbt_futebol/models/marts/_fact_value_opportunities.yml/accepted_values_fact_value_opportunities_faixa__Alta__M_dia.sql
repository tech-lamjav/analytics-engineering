
    
    

with all_values as (

    select
        faixa as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_opportunities`
    group by faixa

)

select *
from all_values
where value_field not in (
    'Alta','Média'
)


