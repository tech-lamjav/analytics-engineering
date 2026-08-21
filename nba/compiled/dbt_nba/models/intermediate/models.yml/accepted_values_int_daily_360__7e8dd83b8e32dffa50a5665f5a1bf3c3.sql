
    
    

with all_values as (

    select
        signal as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`nba`.`int_daily_360_analysis`
    group by signal

)

select *
from all_values
where value_field not in (
    'FORTE','MEDIO','FRACO','SEM_LINHA'
)


