
    
    

with all_values as (

    select
        injury_type as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`int_futebol_desfalques`
    group by injury_type

)

select *
from all_values
where value_field not in (
    'Missing Fixture','Questionable'
)


