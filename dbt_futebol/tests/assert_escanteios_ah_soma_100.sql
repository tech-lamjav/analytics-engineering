{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DO HANDICAP DE ESCANTEIOS (AE#158, market_id=56): a API-Football cota "Home -4.5"
-- e "Away -4.5" como PAR, odds complementares, linha sempre na ótica do mandante — igual ao
-- Handicap de gols (market_id=4). Liquidar pela leitura literal do rótulo inverte um dos
-- lados e produz número plausível e errado (o próprio Victor relatou ter caído nisso antes
-- de validar, ClickUp wdx6zf1tt8). A validação que fecha: Home + Away tem que somar
-- exatamente 100% em cada linha, dentro de tolerância de ponto flutuante.
--
-- Falsificável de propósito: um COUNT(*) = 0 no CTE de linhas emitidas faria a checagem de
-- soma passar por VACUIDADE (nenhum grupo pra comparar) se o mercado ainda não estivesse
-- declarado em futebol_conjunto_saidas() — daí o canário `sem_emissao` abaixo, que falha
-- sozinho até o dia em que o mercado 56 realmente emitir valor.

WITH ah56 AS (
    SELECT
        fixture_id,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key,
        janela_usada,
        outcome_side,
        prob_justa_fechamento
    FROM {{ ref('int_futebol_odds_devig') }}
    WHERE market_id = 56
      AND prob_justa_fechamento IS NOT NULL
),

somado AS (
    SELECT
        fixture_id,
        line_key,
        janela_usada,
        SUM(prob_justa_fechamento) AS soma_prob_justa,
        COUNT(*)                   AS n_lados
    FROM ah56
    GROUP BY 1, 2, 3
),

divergente AS (
    SELECT
        fixture_id,
        line_key,
        janela_usada,
        soma_prob_justa,
        n_lados,
        'soma das probabilidades justas de Home+Away do mercado 56 não bate 100% — liquidação provavelmente lida pelo rótulo, não pela ótica do mandante' AS diagnostico
    FROM somado
    WHERE n_lados <> 2
       OR ABS(soma_prob_justa - 1.0) > 1e-6
),

sem_emissao AS (
    SELECT
        CAST(NULL AS INT64)    AS fixture_id,
        CAST(NULL AS STRING)   AS line_key,
        CAST(NULL AS STRING)   AS janela_usada,
        CAST(NULL AS FLOAT64)  AS soma_prob_justa,
        CAST(NULL AS INT64)    AS n_lados,
        'nenhuma linha do mercado 56 emitiu valor — a checagem de soma passaria por vacuidade; declarar 56 em futebol_conjunto_saidas() (AE#158)' AS diagnostico
    FROM (SELECT COUNT(*) AS n FROM ah56)
    WHERE n = 0
)

SELECT * FROM divergente
UNION ALL
SELECT * FROM sem_emissao
