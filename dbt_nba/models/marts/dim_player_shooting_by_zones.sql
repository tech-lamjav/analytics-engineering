{{
  config(
    description='NBA players shooting by zones for analysis',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH dim_player_shooting_by_zones AS (

    SELECT
       *
    FROM {{ ref('stg_season_averages_shooting_by_zone') }}
)

SELECT * FROM dim_player_shooting_by_zones