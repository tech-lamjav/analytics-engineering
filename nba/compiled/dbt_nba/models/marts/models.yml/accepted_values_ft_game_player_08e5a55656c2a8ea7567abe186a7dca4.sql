
    
    

with all_values as (

    select
        stat_vs_line as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`nba`.`ft_game_player_stats`
    group by stat_vs_line

)

select *
from all_values
where value_field not in (
    'over','under','push'
)


