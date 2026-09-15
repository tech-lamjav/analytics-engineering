
    
    

with all_values as (

    select
        position as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`dim_players`
    group by position

)

select *
from all_values
where value_field not in (
    'Attacker','Midfielder','Defender','Goalkeeper'
)


