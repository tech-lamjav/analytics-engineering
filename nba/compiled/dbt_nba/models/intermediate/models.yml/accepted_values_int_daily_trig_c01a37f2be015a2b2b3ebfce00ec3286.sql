
    
    

with all_values as (

    select
        fatigue_level as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`nba`.`int_daily_triggers`
    group by fatigue_level

)

select *
from all_values
where value_field not in (
    'ALTA','MEDIA','BAIXA'
)


