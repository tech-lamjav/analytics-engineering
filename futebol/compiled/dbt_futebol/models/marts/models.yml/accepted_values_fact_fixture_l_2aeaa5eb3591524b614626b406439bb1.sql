
    
    

with all_values as (

    select
        lineup_phase as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_fixture_lineups`
    group by lineup_phase

)

select *
from all_values
where value_field not in (
    'confirmed','real'
)


