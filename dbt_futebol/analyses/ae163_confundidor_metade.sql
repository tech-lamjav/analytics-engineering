{#
    AE#163 — diagnóstico (contagem, não ROI) do split temporal do OOS: NTILE(2) sobre
    kickoff_utc na janela viva (16/06-13/09) corta ANTES/DEPOIS do início das temporadas
    europeias — checando se "metade 1" e "metade 2" são, na prática, um split por
    competição/continente em vez de um split temporal neutro. Só contagem, não agrega
    ROI/ganho — não fere a disciplina de pré-registro do #163.
#}

WITH {{ ae161_base_escanteios(cutoff=none, janela_fixa=none, gates_do_board=true) }},

apostas_unica AS (
    SELECT *
    FROM apostas
    WHERE min_jogos >= 10
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, outcome_side
        ORDER BY n_casas DESC, ABS(line_value) ASC, line_value ASC
    ) = 1
),

metades AS (
    SELECT fixture_id, kickoff_utc, competition,
           NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc, competition FROM apostas_unica)
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
