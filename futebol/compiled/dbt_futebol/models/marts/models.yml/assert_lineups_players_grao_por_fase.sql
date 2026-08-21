





with validation_errors as (

    select
        fixture_id, player_id, lineup_phase
    from `smartbetting-dados`.`futebol`.`fact_fixture_lineups_players`
    group by fixture_id, player_id, lineup_phase
    having count(*) > 1

)

select *
from validation_errors


