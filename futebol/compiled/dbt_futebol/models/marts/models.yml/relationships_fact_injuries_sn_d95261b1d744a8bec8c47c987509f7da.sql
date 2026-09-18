
    
    

with child as (
    select team_id as from_field
    from `smartbetting-dados`.`futebol`.`fact_injuries_snapshot`
    where team_id is not null
),

parent as (
    select team_id as to_field
    from `smartbetting-dados`.`futebol`.`dim_teams`
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null


