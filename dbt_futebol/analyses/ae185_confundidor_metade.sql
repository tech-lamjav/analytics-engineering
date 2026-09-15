{#
    AE#185 — diagnóstico (contagem, não ROI) do split temporal do OOS: NTILE(2) sobre
    kickoff_utc na janela viva do Total de escanteios — checando se "metade 1" e
    "metade 2" são, na prática, um split por competição/continente em vez de um split
    temporal neutro. Mesma checagem que `ae163_confundidor_metade.sql` fez pro Handicap
    (achou ~80% Brasil/CONMEBOL na metade 1 contra calendário europeu completo na metade
    2). Só contagem, não agrega ROI/ganho.
#}

WITH {{ ae183_base_escanteios_total(cutoff=none, janela_fixa=none, gates_do_board=true) }},

metades AS (
    SELECT fixture_id, kickoff_utc, competition,
           NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc, competition FROM apostas)
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
