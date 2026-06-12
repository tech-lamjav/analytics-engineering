{{ config(
    materialized='view',
    description='View de confronto direto (head-to-head) sobre fact_fixtures — zero chamada extra à API (/fixtures/headtohead é redundante: os jogos já estão na tabela mãe). h2h_pair_key = "menorId-maiorId" (LEAST/GREATEST dos team_ids) identifica o par independente do mando. Só jogos finalizados (FT/AET/PEN — inclui mata-mata da Copa por prorrogação/pênaltis). Demais colunas espelham fact_fixtures 1:1; recriada no run diário logo após fact_fixtures.'
) }}

SELECT
    -- chave do par independente do mando: WHERE h2h_pair_key = 'X-Y' traz
    -- todos os confrontos entre X e Y (X < Y), seja quem for o mandante
    CONCAT(
        CAST(LEAST(home_team_id, away_team_id) AS STRING),
        '-',
        CAST(GREATEST(home_team_id, away_team_id) AS STRING)
    ) AS h2h_pair_key,
    *
FROM {{ ref('fact_fixtures') }}
WHERE status_short IN ('FT', 'AET', 'PEN')
