
    
    

with dbt_test__target as (

  select player_id as unique_field
  from `smartbetting-dados`.`nba`.`int_game_player_stats_last_game_text`
  where player_id is not null

)

select
    unique_field,
    count(*) as n_records

from dbt_test__target
group by unique_field
having count(*) > 1


