
-- Guard de regressão da Task 0 (look-ahead).
-- No PRIMEIRO jogo de um time numa (competição, temporada) não existe passado: played_total tem
-- de ser 0 e rank/médias têm de ser NULL. Era exatamente aqui que o modelo antigo entregava a
-- temporada FECHADA (played_total=38, tabela final) a um jogo da rodada 1.
-- Falha = alguma fonte voltou a ser lida sem âncora no kickoff.

WITH primeiro_jogo AS (
    SELECT
        fixture_id,
        team_id,
        competition,
        season,
        kickoff_utc,
        played_total,played_total_disponivel,
        rank,
        goals_for_avg_home
    FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY team_id
        ORDER BY kickoff_utc
    ) = 1
)

SELECT *
FROM primeiro_jogo
WHERE played_total != 0
   OR played_total_disponivel != 0
   OR rank IS NOT NULL
   OR goals_for_avg_home IS NOT NULL