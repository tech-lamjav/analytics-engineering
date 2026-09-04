
    
    

with all_values as (

    select
        outcome as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
    group by outcome

)

select *
from all_values
where value_field not in (
    'Home','Draw','Away'
)


