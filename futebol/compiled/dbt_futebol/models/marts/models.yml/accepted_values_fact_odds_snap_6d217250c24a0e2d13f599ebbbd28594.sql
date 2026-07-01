
    
    

with all_values as (

    select
        collection_window as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    group by collection_window

)

select *
from all_values
where value_field not in (
    't24h','t1h','t15m'
)


