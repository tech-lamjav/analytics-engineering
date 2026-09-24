
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
-- Mercado ausente do declarado NÃO acende sozinho se estiver em
-- futebol_mercados_mudos_confirmados() — decisão registrada de ficar mudo (AE#164), não
-- esquecimento. Ver o comentário ao lado do macro pra cada motivo.
--
-- ⚠️ A supressão do "mudo confirmado" só vale pro diagnóstico 1 (órfão). Se um mercado
-- ESTIVER declarado (tem conjunto_esperado) e AINDA ASSIM sobrar na lista de mudos por
-- alguém esquecer de tirá-lo de lá, o diagnóstico 2 (mapa envelhecido) continua rodando
-- pra ele — as duas listas não são mutuamente exclusivas por dbt, então a checagem abaixo
-- que impede a sobreposição de existir em silêncio é obrigatória (achado do code-review).
--
-- ⚠️ VERDE POR VACUIDADE hoje: não há mercado órfão nem mapa desatualizado na base. Ela é
-- infalsificável em produção até o dia em que disparar — que é exatamente o dia em que
-- precisamos confiar nela.

WITH declarado AS (
    SELECT * FROM UNNEST([
        STRUCT(1 AS market_id, 3 AS conjunto_esperado),
        STRUCT(4 AS market_id, 2 AS conjunto_esperado),
        STRUCT(5 AS market_id, 2 AS conjunto_esperado),
        STRUCT(6 AS market_id, 2 AS conjunto_esperado),
        STRUCT(8 AS market_id, 2 AS conjunto_esperado),
        STRUCT(12 AS market_id, 3 AS conjunto_esperado),
        STRUCT(45 AS market_id, 2 AS conjunto_esperado),
        STRUCT(56 AS market_id, 2 AS conjunto_esperado),
        STRUCT(57 AS market_id, 2 AS conjunto_esperado),
        STRUCT(58 AS market_id, 2 AS conjunto_esperado)
    ])
),

mudo_confirmado AS (
    SELECT * FROM UNNEST([
        77
    ]) AS market_id
),

observado AS (
    SELECT
        market_id,
        MAX(n_outcomes_valor) AS conjunto_maximo_observado,
        COUNT(*)              AS linhas
    FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
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
LEFT JOIN mudo_confirmado m ON m.market_id = o.market_id
WHERE (d.conjunto_esperado IS NULL AND m.market_id IS NULL)
   OR (d.conjunto_esperado IS NOT NULL AND o.conjunto_maximo_observado <> d.conjunto_esperado)
ORDER BY o.linhas DESC