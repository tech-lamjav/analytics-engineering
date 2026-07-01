





with validation_errors as (

    select
        league_id, season, snapshot_date, group_name, team_id
    from `smartbetting-dados`.`futebol`.`fact_standings_snapshot`
    group by league_id, season, snapshot_date, group_name, team_id
    having count(*) > 1

)

select *
from validation_errors


