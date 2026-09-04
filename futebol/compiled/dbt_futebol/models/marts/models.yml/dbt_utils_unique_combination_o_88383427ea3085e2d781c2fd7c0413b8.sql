





with validation_errors as (

    select
        league_id, season_year
    from `smartbetting-dados`.`futebol`.`dim_leagues`
    group by league_id, season_year
    having count(*) > 1

)

select *
from validation_errors


