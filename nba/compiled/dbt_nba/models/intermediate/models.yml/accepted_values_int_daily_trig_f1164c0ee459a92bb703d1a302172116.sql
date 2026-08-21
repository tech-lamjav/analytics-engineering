
    
    

with all_values as (

    select
        trigger_status as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`nba`.`int_daily_triggers`
    group by trigger_status

)

select *
from all_values
where value_field not in (
    'Out','Doubtful','Questionable'
)


