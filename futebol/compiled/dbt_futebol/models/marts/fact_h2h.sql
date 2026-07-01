

SELECT
    -- chave do par independente do mando: WHERE h2h_pair_key = 'X-Y' traz
    -- todos os confrontos entre X e Y (X < Y), seja quem for o mandante
    CONCAT(
        CAST(LEAST(home_team_id, away_team_id) AS STRING),
        '-',
        CAST(GREATEST(home_team_id, away_team_id) AS STRING)
    ) AS h2h_pair_key,
    *
FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
WHERE status_short IN ('FT', 'AET', 'PEN')