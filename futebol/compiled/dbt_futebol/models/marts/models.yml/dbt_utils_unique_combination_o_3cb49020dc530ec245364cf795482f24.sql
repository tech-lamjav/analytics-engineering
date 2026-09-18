





with validation_errors as (

    select
        team_id, competition_id, season
    from `smartbetting-dados`.`futebol`.`fact_team_season_stats`
    group by team_id, competition_id, season
    having count(*) > 1

)

select *
from validation_errors


