
    
    

with dbt_test__target as (

  select team_id as unique_field
  from `smartbetting-dados`.`nba`.`dim_teams`
  where team_id is not null

)

select
    unique_field,
    count(*) as n_records

from dbt_test__target
group by unique_field
having count(*) > 1


