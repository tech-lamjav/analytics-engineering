
    
    

with all_values as (

    select
        valor_fonte as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    group by valor_fonte

)

select *
from all_values
where value_field not in (
    'pinnacle','consenso'
)


