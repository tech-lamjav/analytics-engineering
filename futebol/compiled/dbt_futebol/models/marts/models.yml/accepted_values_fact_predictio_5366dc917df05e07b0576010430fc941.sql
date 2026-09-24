
    
    

with all_values as (

    select
        collection_window as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_predictions_api`
    group by collection_window

)

select *
from all_values
where value_field not in (
    't2h','daily'
)


