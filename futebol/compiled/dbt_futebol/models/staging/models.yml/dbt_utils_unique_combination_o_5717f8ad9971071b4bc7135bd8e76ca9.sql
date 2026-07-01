





with validation_errors as (

    select
        team_id, requested_league_id, requested_season
    from `smartbetting-dados`.`futebol`.`stg_futebol_team_season_stats`
    group by team_id, requested_league_id, requested_season
    having count(*) > 1

)

select *
from validation_errors


