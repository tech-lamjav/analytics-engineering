





with validation_errors as (

    select
        league_id, season, snapshot_date, fixture_id, player_id, injury_type, injury_reason
    from `smartbetting-dados`.`futebol`.`fact_injuries_snapshot`
    group by league_id, season, snapshot_date, fixture_id, player_id, injury_type, injury_reason
    having count(*) > 1

)

select *
from validation_errors


