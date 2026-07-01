
    
    

with all_values as (

    select
        outcome_side as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    group by outcome_side

)

select *
from all_values
where value_field not in (
    'Over','Under','Home','Away','Draw','Yes','No','1X','12','X2'
)


