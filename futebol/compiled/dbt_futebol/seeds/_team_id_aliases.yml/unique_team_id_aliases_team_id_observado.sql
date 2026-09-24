
    
    

with dbt_test__target as (

  select team_id_observado as unique_field
  from `smartbetting-dados`.`futebol`.`team_id_aliases`
  where team_id_observado is not null

)

select
    unique_field,
    count(*) as n_records

from dbt_test__target
group by unique_field
having count(*) > 1


