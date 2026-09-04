
    
    

with all_values as (

    select
        origem as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto`
    group by origem

)

select *
from all_values
where value_field not in (
    'recomputacao','registro'
)


