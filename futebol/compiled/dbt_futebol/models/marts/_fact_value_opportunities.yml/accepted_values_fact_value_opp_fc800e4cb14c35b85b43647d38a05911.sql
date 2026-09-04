
    
    

with all_values as (

    select
        score_versao as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_opportunities`
    group by score_versao

)

select *
from all_values
where value_field not in (
    'contexto_v1'
)


