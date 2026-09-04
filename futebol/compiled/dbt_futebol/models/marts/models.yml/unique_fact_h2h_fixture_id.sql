
    
    

with dbt_test__target as (

  select fixture_id as unique_field
  from `smartbetting-dados`.`futebol`.`fact_h2h`
  where fixture_id is not null

)

select
    unique_field,
    count(*) as n_records

from dbt_test__target
group by unique_field
having count(*) > 1


