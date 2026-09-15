






with recency as (

    select 

      
      
        max(coletado_em) as most_recent

    from `smartbetting-dados`.`futebol`.`stg_futebol_injuries_coleta`

    

)

select

    
    most_recent,
    cast(

        datetime_add(
            cast( current_timestamp() as datetime),
        interval -2 day
        )

 as timestamp) as threshold

from recency
where most_recent < cast(

        datetime_add(
            cast( current_timestamp() as datetime),
        interval -2 day
        )

 as timestamp)

