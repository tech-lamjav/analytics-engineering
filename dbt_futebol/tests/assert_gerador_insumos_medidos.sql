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

casos AS (
    SELECT
        'int_futebol_premissas_btts' AS modelo,
        outcome,
        TO_JSON_STRING(esperado) AS esperado,
        TO_JSON_STRING({{ futebol_insumos_medidos('int_futebol_premissas_btts') }}) AS gerado
    FROM btts
)

SELECT modelo, outcome, esperado, gerado
FROM casos
WHERE esperado != gerado
