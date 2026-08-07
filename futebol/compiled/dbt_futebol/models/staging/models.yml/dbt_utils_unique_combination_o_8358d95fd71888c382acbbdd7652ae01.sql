





with validation_errors as (

    select
        fixture_id, player_id
    from `smartbetting-dados`.`futebol`.`stg_futebol_fixture_player_stats`
    group by fixture_id, player_id
    having count(*) > 1

)

select *
from validation_errors


