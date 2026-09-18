





with validation_errors as (

    select
        fixture_id, lineup_phase, player_id
    from `smartbetting-dados`.`futebol`.`stg_futebol_fixture_lineups_players`
    group by fixture_id, lineup_phase, player_id
    having count(*) > 1

)

select *
from validation_errors


