





with validation_errors as (

    select
        game_id, team_id
    from `smartbetting-dados`.`nba`.`int_games_teams_pilled`
    group by game_id, team_id
    having count(*) > 1

)

select *
from validation_errors


