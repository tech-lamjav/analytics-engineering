





with validation_errors as (

    select
        team_id, season
    from `smartbetting-dados`.`nba`.`stg_team_season_averages_shooting_by_zone_opponent`
    group by team_id, season
    having count(*) > 1

)

select *
from validation_errors


