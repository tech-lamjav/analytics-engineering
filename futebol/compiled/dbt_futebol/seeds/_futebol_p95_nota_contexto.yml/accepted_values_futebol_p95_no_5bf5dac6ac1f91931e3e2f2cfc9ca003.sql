
    
    

with all_values as (

    select
        market as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto`
    group by market

)

select *
from all_values
where value_field not in (
    'match_winner','asian_handicap','goals_over_under','btts','double_chance'
)


