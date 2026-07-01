
    
    

with all_values as (

    select
        team_side as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_fixture_player_stats`
    group by team_side

)

select *
from all_values
where value_field not in (
    'home','away'
)


