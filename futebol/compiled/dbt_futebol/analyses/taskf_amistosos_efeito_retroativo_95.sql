

WITH antes AS (
    SELECT * FROM `smartbetting-dados.futebol.int_futebol_team_form_pit`
    WHERE competition_id IN (1, 5)
),

depois AS (
    -- Exige o build toggled acima já ter rodado. Se `taskF` estiver no estado default (sem
    -- amistosos), esta CTE fica idêntica a `antes` e todo delta sai zero — não é ausência de
    -- efeito, é o experimento não ter sido montado.
    SELECT * FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`
    WHERE competition_id IN (1, 5)
),

comparado AS (
    SELECT
        a.competition,
        a.fixture_id,
        a.team_id,
        a.played_total                                          AS pt_antes,
        d.played_total                                          AS pt_depois,
        SAFE_DIVIDE(a.wins_total, a.played_total) * 100          AS winrate_antes,
        SAFE_DIVIDE(d.wins_total, d.played_total) * 100          AS winrate_depois
    FROM antes a
    JOIN depois d USING (fixture_id, team_id)
)

SELECT
    competition,
    COUNT(*)                                                              AS n_ancoras,
    COUNTIF(pt_antes = 0)                                                 AS n_sem_historico_antes,
    COUNTIF(pt_antes = 0 AND pt_depois > 0)                               AS n_ganhou_historico_do_zero,
    ROUND(AVG(pt_depois - pt_antes), 2)                                   AS delta_medio_played_total,
    ROUND(AVG(ABS(COALESCE(winrate_depois, 0) - COALESCE(winrate_antes, 0))), 2) AS delta_medio_pp_winrate,
    ROUND(APPROX_QUANTILES(ABS(COALESCE(winrate_depois, 0) - COALESCE(winrate_antes, 0)), 2)[OFFSET(1)], 2)
                                                                           AS mediana_pp_winrate
FROM comparado
GROUP BY competition
ORDER BY competition