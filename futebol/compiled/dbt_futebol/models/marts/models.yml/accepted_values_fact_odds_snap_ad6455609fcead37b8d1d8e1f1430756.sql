
    
    

with all_values as (

    select
        competition as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    group by competition

)

select *
from all_values
where value_field not in (
    'brasileirao','copa_mundo','serie_b','copa_do_brasil','libertadores','sudamericana','la_liga','premier_league','champions_league','serie_a_ita','bundesliga','ligue_1','primeira_liga'
)


