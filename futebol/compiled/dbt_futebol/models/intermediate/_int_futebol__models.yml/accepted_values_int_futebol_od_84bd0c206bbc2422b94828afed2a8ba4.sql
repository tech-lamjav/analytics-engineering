
    
    

with all_values as (

    select
        janela_usada as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    group by janela_usada

)

select *
from all_values
where value_field not in (
    'daily','t24h','t1h','t15m'
)


