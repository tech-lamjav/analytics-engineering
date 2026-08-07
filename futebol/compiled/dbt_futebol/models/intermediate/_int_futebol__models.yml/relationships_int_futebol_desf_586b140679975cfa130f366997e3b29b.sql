
    
    

with child as (
    select fixture_id as from_field
    from `smartbetting-dados`.`futebol`.`int_futebol_desfalques`
    where fixture_id is not null
),

parent as (
    select fixture_id as to_field
    from `smartbetting-dados`.`futebol`.`fact_fixtures`
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null


