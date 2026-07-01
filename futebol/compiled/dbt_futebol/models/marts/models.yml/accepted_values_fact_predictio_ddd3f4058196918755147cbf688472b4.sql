
    
    

with all_values as (

    select
        competition as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_predictions_api`
    group by competition

)

select *
from all_values
where value_field not in (
    'brasileirao','copa_mundo'
)


