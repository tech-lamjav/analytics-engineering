{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE RECONSTRUÇÃO DA NOTA DE CONTEXTO (#103, ADR 0012): a coluna GRAVADA no funil
-- bate com a RECOMPOSTA a partir de `pts_premissas` e das penalidades de contexto.
--
-- O modo de falha que ela existe para pegar é o que a sentinela não alcança: o funil
-- FUGIR do macro. `assert_nota_contexto_sem_preco` prova que não há preço dentro de
-- `futebol_nota_contexto()`; ela não prova que é esse macro que o modelo usa. Alguém que
-- escreva a soma à mão na CTE `scored` — para "consertar" um número, ou copiando o ramo
-- do board — passa por ela em silêncio e cai aqui.
--
-- As duas leem o MESMO macro de propósito. Não é redundância: é o que faz esta guarda
-- comparar a coluna com a DEFINIÇÃO e não com uma segunda cópia da definição, que é o
-- erro que o cabeçalho do `futebol_expurgo.sql` já registrou uma vez.
--
-- ⚠️ `IS DISTINCT FROM`, e não `!=`. A "12" da Dupla Chance não tem premissa a avaliar:
-- `pts_premissas` chega NULL, `GREATEST(NULL, 0)` é NULL, e a coluna gravada é NULL. Com
-- `!=` os dois NULLs devolveriam NULL, o `WHERE` descartaria a linha e a guarda ficaria
-- CEGA justamente na saída em que a aritmética é mais fácil de errar. Com
-- `IS DISTINCT FROM`, NULL contra NULL é igualdade e NULL contra número é divergência.
--
-- ⚠️ ESCOPADA AO QUE AINDA É GRAVÁVEL, e o aceite da issue pede "em toda linha". A letra
-- do aceite e o append-only não cabem juntos: a coluna chega por `append_new_columns`, e
-- o funil só escreve linha cujo kickoff está no futuro (ADR 0011). Toda linha de jogo já
-- apitado antes do deploy da A1 fica com `nota_contexto` NULL para sempre — não porque a
-- composição errou, mas porque a história está congelada, que é a coisa inteira que a #96
-- construiu. Uma guarda literal nasceria VERMELHA sobre o funil inteiro de antes de hoje,
-- e o aceite irmão desta issue diz que guarda nova nasce em ZERO (precedente da #33).
--
-- O escopo é o MESMO predicado que governa a escrita — `futebol_funil_e_gravavel()`, o
-- macro que o modelo e as outras duas guardas do funil já leem, nunca copiado. Dentro
-- dele a cobrança é a do aceite, linha a linha, sem tolerância.
--
-- ⚠️ O QUE SAI JUNTO COM O ESCOPO: uma divergência confinada a linha já congelada passa
-- por aqui em silêncio. Não há como ser diferente — depois do apito ninguém reescreve
-- aquela linha, então não existe defeito CORRENTE a corrigir ali; o que existe é registro
-- de época, e reescrevê-lo seria o dano que a ADR 0011 proíbe.
--
-- ⚠️ A SEGUNDA DIREÇÃO — linha gravável com a coluna VAZIA — está aqui e é o que dá
-- mordida à guarda no dia do deploy. Sem ela, um `nota_contexto` que nunca fosse
-- preenchido (coluna que não chegou ao esquema, `append_new_columns` que não rodou) seria
-- lido como "reconstrói perfeitamente": NULL contra NULL fecha. Com ela, a linha que
-- ainda podia ser escrita e não tem nota — tendo `pts_premissas` — acende.

WITH funil AS (
    SELECT
        fixture_id,
        market,
        outcome,
        line_key,
        janela,
        kickoff_utc,
        pts_premissas,
        penalidades_especificas_pts,
        nota_contexto,
        -- a recomposição, do MESMO macro que o modelo usa. As duas colunas de que ele
        -- depende chegam com o nome que ele espera, direto da tabela.
        {{ futebol_nota_contexto() }} AS nota_contexto_recomposta
    FROM {{ ref('fact_value_funnel') }}
    -- só o que o funil ainda escreveria hoje — ver o cabeçalho.
    WHERE {{ futebol_funil_e_gravavel('kickoff_utc') }}
)

SELECT
    fixture_id,
    market,
    outcome,
    line_key,
    janela,
    pts_premissas,
    penalidades_especificas_pts,
    nota_contexto,
    nota_contexto_recomposta,
    CASE
        WHEN nota_contexto IS NULL AND pts_premissas IS NOT NULL
            THEN 'linha ainda gravável com nota_contexto vazia e premissa avaliada — a coluna não chegou ao esquema (append_new_columns não rodou?) ou o modelo parou de preenchê-la'
        ELSE 'nota_contexto gravada não bate com a recomposta de pts_premissas − penalidades de contexto — o modelo fugiu de futebol_nota_contexto()'
    END AS diagnostico
FROM funil
WHERE nota_contexto IS DISTINCT FROM nota_contexto_recomposta
   OR (nota_contexto IS NULL AND pts_premissas IS NOT NULL)
ORDER BY fixture_id, market, outcome, line_key, janela
