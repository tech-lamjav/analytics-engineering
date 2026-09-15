
    
    

with all_values as (

    select
        source as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`dim_players`
    group by source

)

select *
from all_values
where value_field not in (
    'catalog','fixture_only'
)


