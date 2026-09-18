





with validation_errors as (

    select
        team_id, group_name, requested_league_id, requested_season, snapshot_date
    from `smartbetting-dados`.`futebol`.`stg_futebol_standings`
    group by team_id, group_name, requested_league_id, requested_season, snapshot_date
    having count(*) > 1

)

select *
from validation_errors


