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
-- macro que o modelo e as outras duas guardas do funil já leem, nunca copiado, e aplicado
-- sobre o MESMO insumo que elas (o kickoff corrente de `fact_fixtures`; ver o ⚠️ na CTE
-- abaixo). Dentro dele a cobrança é a do aceite, linha a linha, sem tolerância.
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

-- ⚠️ O KICKOFF VEM DE `fact_fixtures`, E NÃO DA COLUNA GRAVADA NO FUNIL. Os dois quase
-- sempre são o mesmo instante, e é aí que mora a armadilha: o `kickoff_utc` do funil é o
-- da ÚLTIMA ESCRITA, e o predicado de gravabilidade lê o kickoff CORRENTE — está escrito
-- no cabeçalho do macro e na descrição do modelo ("lê o kickoff corrente, não o que estava
-- lá quando a linha foi escrita"). Jogo adiado (`PST`/`SUSP`) separa os dois: o corrente
-- vai para o futuro e o gravado fica no passado. Com a coluna gravada, esta guarda
-- EXCLUIRIA uma linha que o funil voltou a escrever — ponto cego —, e o inverso produziria
-- vermelho sem defeito.
--
-- É também o que as duas guardas irmãs fazem (`assert_funil_paridade_com_board`,
-- `assert_funil_reconcilia_com_devig`): as duas juntam `fact_fixtures` e aplicam o macro
-- sobre o kickoff de lá. `LEFT` + o `COALESCE(..., TRUE)` de dentro do macro mantêm o
-- fail-open dos dois lados — fixture ausente continua gravável, e continua cobrado aqui.
WITH fixtures AS (
    SELECT
        fixture_id,
        kickoff_utc AS _fx_kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

funil AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.janela,
        f.pts_premissas,
        f.penalidades_especificas_pts,
        f.nota_contexto,
        -- a recomposição, do MESMO macro que o modelo usa. As duas colunas de que ele
        -- depende chegam com o nome que ele espera, direto da tabela.
        {{ futebol_nota_contexto() }} AS nota_contexto_recomposta
    FROM {{ ref('fact_value_funnel') }} f
    LEFT JOIN fixtures fx USING (fixture_id)
    -- só o que o funil ainda escreveria hoje — ver o cabeçalho.
    WHERE {{ futebol_funil_e_gravavel('fx._fx_kickoff_utc') }}
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
