
    
    

with all_values as (

    select
        lado as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto`
    group by lado

)

select *
from all_values
where value_field not in (
    'Home','Draw','Away','Over','Under','Favorito','Azarao','Pick','Yes','No','unico'
)


