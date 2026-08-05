{{ config(tags=['guarda']) }}
-- Guard de regressão da Task 0 (item D).
-- Todo desfalque que chega na premissa tem de vir de um snapshot COLETADO ANTES DO APITO.
-- O log de /injuries da API é retroativo (99,6% das linhas são pós-jogo, inclusive de quem se
-- machucou durante a partida): sem esta âncora o backtest lê um dado que produção não tem.
-- Falha = alguém removeu o filtro extracted_at < kickoff_utc.

WITH desfalques AS (
    SELECT DISTINCT fixture_id, team_id, player_id
    FROM {{ ref('int_futebol_desfalques') }}
),

-- Menor instante de coleta disponível p/ aquele (fixture, time, jogador).
coleta AS (
    SELECT
        i.fixture_id,
        i.team_id,
        i.player_id,
        MIN(i.extracted_at) AS primeira_coleta,
        ANY_VALUE(f.kickoff_utc) AS kickoff_utc
    FROM {{ ref('fact_injuries_snapshot') }} i
    JOIN {{ ref('fact_fixtures') }} f USING (fixture_id)
    GROUP BY i.fixture_id, i.team_id, i.player_id
)

SELECT d.*, c.primeira_coleta, c.kickoff_utc
FROM desfalques d
JOIN coleta c
    USING (fixture_id, team_id, player_id)
WHERE c.primeira_coleta >= c.kickoff_utc
