





with validation_errors as (

    select
        fixture_id, lineup_phase, team_id
    from `smartbetting-dados`.`futebol`.`stg_futebol_fixture_lineups`
    group by fixture_id, lineup_phase, team_id
    having count(*) > 1

)

select *
from validation_errors


