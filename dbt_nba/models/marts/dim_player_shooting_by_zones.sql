{{
  config(
    description='NBA players shooting by zones for analysis',
    labels={'domain': 'bi', 'category': 'analytics'}
  )
}}

WITH dim_player_shooting_by_zones AS (

    SELECT
       * EXCEPT(loaded_at)
    FROM {{ ref('stg_season_averages_shooting_by_zone') }}
)

SELECT
    *,
    CURRENT_TIMESTAMP() AS loaded_at
FROM dim_player_shooting_by_zones