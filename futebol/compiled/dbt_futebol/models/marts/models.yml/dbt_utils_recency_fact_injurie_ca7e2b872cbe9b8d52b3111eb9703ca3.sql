






with recency as (

    select 

      
      
        cast(max(snapshot_date) as date) as most_recent

    from `smartbetting-dados`.`futebol`.`fact_injuries_snapshot`

    

)

select

    
    most_recent,
    cast(

        datetime_add(
            cast( current_timestamp() as datetime),
        interval -2 day
        )

 as date) as threshold

from recency
where most_recent < cast(

        datetime_add(
            cast( current_timestamp() as datetime),
        interval -2 day
        )

 as date)

