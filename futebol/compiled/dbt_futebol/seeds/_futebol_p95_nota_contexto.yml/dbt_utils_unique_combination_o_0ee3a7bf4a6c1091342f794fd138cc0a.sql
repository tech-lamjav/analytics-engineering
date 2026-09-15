





with validation_errors as (

    select
        market, lado
    from `smartbetting-dados`.`futebol`.`futebol_p95_nota_contexto`
    group by market, lado
    having count(*) > 1

)

select *
from validation_errors


