





with validation_errors as (

    select
        fixture_id, team_id
    from `smartbetting-dados`.`futebol`.`fact_fixture_lineups`
    group by fixture_id, team_id
    having count(*) > 1

)

select *
from validation_errors


