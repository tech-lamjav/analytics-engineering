





with validation_errors as (

    select
        fixture_id, bookmaker_id, market_id, outcome_label, collection_window
    from `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    group by fixture_id, bookmaker_id, market_id, outcome_label, collection_window
    having count(*) > 1

)

select *
from validation_errors


