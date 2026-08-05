{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DO MAPA (spec #22): o conjunto declarado em futebol_conjunto_saidas() tem que
-- corresponder ao que a base realmente tem. Cobre os DOIS pontos cegos do fail-closed:
--
-- 1. MERCADO ÓRFÃO — presente nas odds e ausente do macro. Sem esta guarda, um mercado novo
--    nasceria MUDO EM SILÊNCIO: a regra de emissão o rejeitaria inteiro e ninguém saberia,
--    porque "não emitir" é indistinguível de "não ter dado".
-- 2. MAPA ENVELHECIDO — um rótulo novo faz o conjunto real de um mercado declarado crescer
--    (ex.: um 1X2 que passasse a ter 4 saídas). A comparação exata da regra faria o mercado
--    inteiro parar de emitir, de novo em silêncio.
--
-- Compara contra o MÁXIMO observado por mercado, e não contra a contagem por linha, porque
-- linha legitimamente incompleta é o caso NORMAL que a correção trata — usar a contagem por
-- linha faria esta guarda vermelha permanente, que é como uma guarda morre ignorada.
--
-- ⚠️ VERDE POR VACUIDADE hoje: não há mercado órfão nem mapa desatualizado na base. Ela é
-- infalsificável em produção até o dia em que disparar — que é exatamente o dia em que
-- precisamos confiar nela. Por isso existe o unit test de linhas forjadas ao lado.

WITH declarado AS (
    SELECT * FROM UNNEST([
        {%- for mid, n in futebol_conjunto_saidas().items() %}
        STRUCT({{ mid }} AS market_id, {{ n }} AS conjunto_esperado){{ "," if not loop.last }}
        {%- endfor %}
    ])
),

observado AS (
    SELECT
        market_id,
        MAX(n_outcomes_valor) AS conjunto_maximo_observado,
        COUNT(*)              AS linhas
    FROM {{ ref('int_futebol_odds_devig') }}
    GROUP BY market_id
)

SELECT
    o.market_id,
    o.conjunto_maximo_observado,
    d.conjunto_esperado,
    o.linhas,
    CASE
        WHEN d.conjunto_esperado IS NULL THEN 'mercado ausente de futebol_conjunto_saidas() — declarar ou confirmar que deve ficar mudo'
        ELSE 'conjunto real divergente do declarado — o mapa envelheceu e o mercado parou de emitir'
    END AS diagnostico
FROM observado o
LEFT JOIN declarado d ON d.market_id = o.market_id
WHERE d.conjunto_esperado IS NULL
   OR o.conjunto_maximo_observado <> d.conjunto_esperado
ORDER BY o.linhas DESC
