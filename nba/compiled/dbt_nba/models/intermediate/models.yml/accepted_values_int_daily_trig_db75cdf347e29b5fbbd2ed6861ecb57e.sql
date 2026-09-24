
    
    

with all_values as (

    select
        trigger_freshness as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`nba`.`int_daily_triggers`
    group by trigger_freshness

)

select *
from all_values
where value_field not in (
    'NOVA','RECENTE','EXTENDIDA'
)


