{{ config(severity='error') }}
-- TESTE DO GERADOR DE VALOR MEDIDO sobre linhas CONSTRUÍDAS (AE#208). Não lê tabela nenhuma:
-- aplica futebol_insumos_medidos() (macros/premissas_valores_medidos.sql) a linhas
-- sintéticas com as colunas que o modelo de premissas teria na CTE, e compara o array gerado
-- com o esperado. Devolve uma linha por caso que diverge.
--
-- Por que não um unit test do dbt: o `expect` em format: sql exige TODAS as colunas do
-- modelo, e os modelos de premissa têm `dbt_loaded_at = CURRENT_TIMESTAMP()`, que nunca
-- bate; e o format de dicionário não expressa ARRAY. As guardas de reconstrução provam que o
-- fact e o funil copiam o que o modelo publica, mas nenhuma delas olha O QUE o gerador
-- publica — é isto que fica aqui, com as regras que só se veem em linha construída:
--
--   Ambos marcam (AE#208)
--     1. a aplicabilidade é a SAÍDA: Yes publica as 4 premissas do Sim (8 entradas), No as
--        3 do Não (6), e nenhuma premissa atravessa de lado;
--     2. os insumos são do mandante e do visitante (home_*/away_*), não S/O;
--     3. a `defesa_forte` publica o PERCENTUAL DE CLEAN SHEET, a grandeza que o critério
--        compara (a tela mostrava gols sofridos — prop-play-predictor#361);
--     4. insumo sem histórico chega NULL, não 0 (classe (b) do mapa da #41).
--
--   Dupla chance (AE#209)
--     5. insumo BOOLEANO — o veredito de premissa do 1X2 que a DC reusa (x_*) — sai 1.0 ou
--        0.0, e o NULL da cegueira herdada continua NULL. Um IF(x, 1, 0) daria 0 para o
--        NULL, que é o disfarce da classe (b) do mapa da #41; e CAST(bool AS FLOAT64) nem
--        compila no BigQuery;
--     6. as 4 premissas se aplicam às duas saídas (1X e X2), 10 entradas cada.
--
-- A ordem das entradas é a do catálogo futebol_insumos_premissa(), que é a ordem em que o
-- gerador as emite. Os dois lados passam pelo mesmo TO_JSON_STRING, então 25.0 e 25 não
-- divergem por formatação.

WITH btts AS (
    SELECT
        'Yes' AS outcome,
        25.0 AS home_fts_pct, 75.0 AS away_fts_pct,
        1.5  AS home_gf,      1.0  AS away_gf,
        50.0 AS home_cs_pct,  25.0 AS away_cs_pct,
        1 AS home_btts_cnt,    CAST(NULL AS INT64) AS away_btts_cnt,
        0 AS home_no_btts_cnt, CAST(NULL AS INT64) AS away_no_btts_cnt,
        [
            STRUCT('ambos_marcam' AS premissa, 'home_fts_pct' AS insumo, 25.0 AS valor),
            STRUCT('ambos_marcam', 'away_fts_pct', 75.0),
            STRUCT('ataque_dos_dois', 'home_gf', 1.5),
            STRUCT('ataque_dos_dois', 'away_gf', 1.0),
            STRUCT('defesas_vazaveis', 'home_cs_pct', 50.0),
            STRUCT('defesas_vazaveis', 'away_cs_pct', 25.0),
            STRUCT('historico_btts', 'home_btts_cnt', 1.0),
            STRUCT('historico_btts', 'away_btts_cnt', CAST(NULL AS FLOAT64))
        ] AS esperado

    UNION ALL

    SELECT
        'No',
        25.0, 75.0,
        1.5,  1.0,
        50.0, 25.0,
        1,    CAST(NULL AS INT64),
        0,    CAST(NULL AS INT64),
        [
            STRUCT('defesa_forte' AS premissa, 'home_cs_pct' AS insumo, 50.0 AS valor),
            STRUCT('defesa_forte', 'away_cs_pct', 25.0),
            STRUCT('ataque_trava', 'home_fts_pct', 25.0),
            STRUCT('ataque_trava', 'away_fts_pct', 75.0),
            STRUCT('historico_seco', 'home_no_btts_cnt', 0.0),
            STRUCT('historico_seco', 'away_no_btts_cnt', CAST(NULL AS FLOAT64))
        ]
),

dc AS (
    -- 1X: o lado coberto acendeu pela força (TRUE), não pela tabela (FALSE), e o confronto
    -- direto está cego no 1X2 (NULL).
    SELECT
        '1X' AS outcome,
        TRUE AS x_forca_mismatch, FALSE AS x_superioridade_tabela,
        1.25 AS s_ga_total, 0.75 AS o_ga_total, 0.25 AS s_thrash_rate, 0.5 AS o_thrash_rate,
        37.5 AS o_aproveitamento, CAST(NULL AS BOOL) AS x_h2h_favoravel,
        5 AS s_games_last5, 0 AS s_losses_last5,
        [
            STRUCT('lado_coberto_forte' AS premissa, 'x_forca_mismatch' AS insumo, 1.0 AS valor),
            STRUCT('lado_coberto_forte', 'x_superioridade_tabela', 0.0),
            STRUCT('equilibrio_defensivo', 's_ga_total', 1.25),
            STRUCT('equilibrio_defensivo', 'o_ga_total', 0.75),
            STRUCT('equilibrio_defensivo', 's_thrash_rate', 0.25),
            STRUCT('equilibrio_defensivo', 'o_thrash_rate', 0.5),
            STRUCT('adversario_limitado', 'o_aproveitamento', 37.5),
            STRUCT('adversario_limitado', 'x_h2h_favoravel', CAST(NULL AS FLOAT64)),
            STRUCT('invicto_recente', 's_games_last5', 5.0),
            STRUCT('invicto_recente', 's_losses_last5', 0.0)
        ] AS esperado

    UNION ALL

    -- X2: sem histórico nenhum — os insumos numéricos chegam NULL e os booleanos também.
    SELECT
        'X2',
        CAST(NULL AS BOOL), CAST(NULL AS BOOL),
        CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        CAST(NULL AS FLOAT64), TRUE,
        CAST(NULL AS INT64), CAST(NULL AS INT64),
        [
            STRUCT('lado_coberto_forte' AS premissa, 'x_forca_mismatch' AS insumo, CAST(NULL AS FLOAT64) AS valor),
            STRUCT('lado_coberto_forte', 'x_superioridade_tabela', CAST(NULL AS FLOAT64)),
            STRUCT('equilibrio_defensivo', 's_ga_total', CAST(NULL AS FLOAT64)),
            STRUCT('equilibrio_defensivo', 'o_ga_total', CAST(NULL AS FLOAT64)),
            STRUCT('equilibrio_defensivo', 's_thrash_rate', CAST(NULL AS FLOAT64)),
            STRUCT('equilibrio_defensivo', 'o_thrash_rate', CAST(NULL AS FLOAT64)),
            STRUCT('adversario_limitado', 'o_aproveitamento', CAST(NULL AS FLOAT64)),
            STRUCT('adversario_limitado', 'x_h2h_favoravel', 1.0),
            STRUCT('invicto_recente', 's_games_last5', CAST(NULL AS FLOAT64)),
            STRUCT('invicto_recente', 's_losses_last5', CAST(NULL AS FLOAT64))
        ]
),

casos AS (
    SELECT
        'int_futebol_premissas_btts' AS modelo,
        outcome,
        TO_JSON_STRING(esperado) AS esperado,
        TO_JSON_STRING({{ futebol_insumos_medidos('int_futebol_premissas_btts') }}) AS gerado
    FROM btts

    UNION ALL

    SELECT
        'int_futebol_premissas_dc' AS modelo,
        outcome,
        TO_JSON_STRING(esperado) AS esperado,
        TO_JSON_STRING({{ futebol_insumos_medidos('int_futebol_premissas_dc') }}) AS gerado
    FROM dc
)

SELECT modelo, outcome, esperado, gerado
FROM casos
WHERE esperado != gerado
