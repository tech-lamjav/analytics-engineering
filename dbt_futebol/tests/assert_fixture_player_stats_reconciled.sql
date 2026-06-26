{{ config(severity='warn') }}
-- Reconciliação do spine (gêmeo de assert_fixture_stats_reconciled p/ /fixtures/players):
-- fact_fixture_player_stats faz INNER JOIN em fact_fixtures. Um fixture presente no
-- /fixtures/players mas ausente de fact_fixtures some inteiro (todos os jogadores do jogo),
-- encolhendo a base de props/forma individual sem nenhum teste falhar. Retorna (= falha) todo
-- fixture_id presente no stg e ausente do spine. severity warn (mesma justificativa do gêmeo).
SELECT DISTINCT ps.fixture_id
FROM {{ ref('stg_futebol_fixture_player_stats') }} ps
LEFT JOIN {{ ref('fact_fixtures') }} f
    ON ps.fixture_id = f.fixture_id
WHERE f.fixture_id IS NULL
