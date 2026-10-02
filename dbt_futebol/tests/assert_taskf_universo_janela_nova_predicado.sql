{{ config(tags=['taskf']) }}
-- O PREDICADO DO UNIVERSO DA JANELA NOVA (AE#117, ADR 0010 emenda de 29/09, termo 5).
--
-- Falha (devolve linhas) se o predicado de `janela_nova` ou de `janela_nova_nations_league`
-- (macros/taskf_universos.sql) deixar de bater com a declaração da emenda:
--
--   janela    kickoff_utc em [2026-08-04 12:00:00, 2026-10-01 00:00:00) UTC — o limite inferior é o
--             INSTANTE do carimbo da [F], não o fim do dia 04/08; o superior é exclusivo.
--   primário  fora do universo: copa_mundo, nations_league e amistosos (seleções).
--   à parte   a Nations League é medida em universo próprio, com a MESMA janela.
--
-- É um teste SINTÉTICO sobre o macro, sem ler tabela nenhuma: o que ele afirma é o predicado, e o
-- predicado é função de (kickoff_utc, competition). Cada linha do VALUES carrega o veredito
-- esperado escrito À MÃO, a partir da emenda — não recomputado pelo macro, que seria tautologia.
-- As fronteiras são o ponto: 11:59:59 fora / 12:00:00 dentro, 23:59:59 dentro / 00:00:00 fora.
--
-- Não-vacuidade: um VALUES que perdesse linhas passaria em branco, então a contagem esperada é
-- cobrada à parte (bloco `vacuo`).

WITH casos AS (
    SELECT * FROM UNNEST([
        STRUCT(TIMESTAMP('2026-08-04 11:59:59') AS kickoff_utc, 'brasileirao'      AS competition, FALSE AS esperado_primario, FALSE AS esperado_nl),
        STRUCT(TIMESTAMP('2026-08-04 12:00:00'),                'brasileirao',                     TRUE,                       FALSE),
        STRUCT(TIMESTAMP('2026-09-30 23:59:59'),                'la_liga',                         TRUE,                       FALSE),
        STRUCT(TIMESTAMP('2026-10-01 00:00:00'),                'la_liga',                         FALSE,                      FALSE),
        STRUCT(TIMESTAMP('2026-08-20 19:00:00'),                'champions_league',                TRUE,                       FALSE),
        STRUCT(TIMESTAMP('2026-09-10 19:00:00'),                'copa_mundo',                      FALSE,                      FALSE),
        STRUCT(TIMESTAMP('2026-09-10 19:00:00'),                'amistosos',                       FALSE,                      FALSE),
        STRUCT(TIMESTAMP('2026-09-24 19:45:00'),                'nations_league',                  FALSE,                      TRUE),
        STRUCT(TIMESTAMP('2026-08-04 11:59:59'),                'nations_league',                  FALSE,                      FALSE),
        STRUCT(TIMESTAMP('2026-10-01 00:00:00'),                'nations_league',                  FALSE,                      FALSE)
    ])
),

avaliado AS (
    SELECT
        c.*,
        {{ taskf_universo_predicado('janela_nova', 'c.') }}                 AS obtido_primario,
        {{ taskf_universo_predicado('janela_nova_nations_league', 'c.') }}  AS obtido_nl
    FROM casos AS c
),

divergente AS (
    SELECT
        'predicado_diverge_da_emenda' AS motivo,
        TO_JSON_STRING(STRUCT(kickoff_utc, competition, esperado_primario, obtido_primario,
                              esperado_nl, obtido_nl)) AS linha
    FROM avaliado
    WHERE obtido_primario IS DISTINCT FROM esperado_primario
       OR obtido_nl       IS DISTINCT FROM esperado_nl
),

vacuo AS (
    SELECT
        'caso_sumiu' AS motivo,
        TO_JSON_STRING(STRUCT(COUNT(*) AS casos, 10 AS esperados)) AS linha
    FROM avaliado
    HAVING COUNT(*) <> 10
)

SELECT motivo, linha FROM divergente
UNION ALL
SELECT motivo, linha FROM vacuo
