{#
    AE#187 — diagnóstico (contagem, não ROI) do split ESTRATIFICADO por competição:
    NTILE(2) OVER (PARTITION BY competition_id ORDER BY kickoff_utc, fixture_id), em vez
    do NTILE(2) global que `ae185_confundidor_metade.sql` mediu como ~83%
    Brasil/CONMEBOL na metade 1. Partição por `competition_id`, não por `competition`
    (nome) — mesma cautela já registrada em `ae183_base_escanteios_total.sql` (linha ~99)
    sobre nome de competição misturar temporadas. Só contagem, checando se a estratificação
    de fato equilibra a mistura entre as duas metades antes de gastar a medição de ROI.
#}

WITH {{ ae183_base_escanteios_total(cutoff=none, janela_fixa=none, gates_do_board=true) }},

metades AS (
    SELECT fixture_id, kickoff_utc, competition, competition_id,
           NTILE(2) OVER (PARTITION BY competition_id ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc, competition, competition_id FROM apostas)
)

SELECT
    metade,
    competition,
    COUNT(*) AS n_jogos,
    MIN(DATE(kickoff_utc)) AS de,
    MAX(DATE(kickoff_utc)) AS ate
FROM metades
GROUP BY metade, competition
ORDER BY metade, n_jogos DESC
