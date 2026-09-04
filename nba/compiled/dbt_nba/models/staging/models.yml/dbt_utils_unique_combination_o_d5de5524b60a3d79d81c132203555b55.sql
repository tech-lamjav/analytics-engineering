





with validation_errors as (

    select
        team_id, season, play_type
    from `smartbetting-dados`.`nba`.`stg_team_season_averages_playtypes`
    group by team_id, season, play_type
    having count(*) > 1

)

select *
from validation_errors


