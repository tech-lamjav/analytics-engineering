
    
    

with all_values as (

    select
        market as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_opportunities`
    group by market

)

select *
from all_values
where value_field not in (
    'match_winner','goals_over_under','asian_handicap','btts','double_chance'
)


