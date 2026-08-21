
    
    

with all_values as (

    select
        outcome as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_opportunities`
    group by outcome

)

select *
from all_values
where value_field not in (
    'Home','Draw','Away','Over','Under','Yes','No','1X','X2'
)


