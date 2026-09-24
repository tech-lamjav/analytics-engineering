





with validation_errors as (

    select
        team_id, season
    from `smartbetting-dados`.`nba`.`dim_team_playtypes`
    group by team_id, season
    having count(*) > 1

)

select *
from validation_errors


