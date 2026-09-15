
    
    

with all_values as (

    select
        outcome as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
    group by outcome

)

select *
from all_values
where value_field not in (
    '1X','X2'
)


