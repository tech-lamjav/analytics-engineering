
-- COSTURA B da task [F] (issue #49, ticket #55), a invariante que a #54 deixou encomendada — AS
-- DUAS CONTAGENS DE AMOSTRA SE COMPORTAM CONFORME O RECORTE DA CÉLULA, DOS DOIS LADOS.
--
-- `min_jogos` sai da tabela em duas colunas: `jogos_medios_disp` (quantas partidas anteriores
-- EXISTEM no escopo, sem teto) e `jogos_medios_usado` (quantas alimentaram as médias). Sob
-- recorte `temporada` as duas são o MESMO número por construção — sem teto, tudo que existe é
-- usado. Sob `ultimos_10` a segunda satura em 10 e as duas se separam.
--
-- ⚠️ ESCRITA COM AS DUAS PONTAS, e é isso que a distingue de uma guarda decorativa. Exigir só a
-- igualdade nas células de `temporada` passaria em branco se as quatro células virassem
-- `temporada` por engano — todas iguais, tudo verde, e o eixo de recorte simplesmente não teria
-- sido medido. Por isso o outro lado é cobrado junto: numa célula de `ultimos_10`, ALGUMA linha
-- tem de divergir.
--
--   temporada_com_teto     célula de recorte `temporada` com qualquer linha em que disponível ≠
--                          usado. Não deveria existir: o modelo não emite coluna com teto ali.
--   ultimos_10_sem_teto    célula de recorte `ultimos_10` em que NENHUMA linha diverge. Não é
--                          "ninguém tinha mais de 10 partidas" — medido, o disponível chega a
--                          149 —, é o carimbo ter rodado fora de ordem e o dado ser de outra
--                          célula.
--
-- ⚠️ O LADO `ultimos_10` É COBRADO COMO "ALGUMA LINHA DIVERGE", E NÃO "TODAS DIVERGEM". Hoje as
-- 60 linhas divergem nas duas células com teto, mas isso é medição, não construção: uma premissa
-- que só acendesse em jogo de time novo teria disponível < 10 em todas as suas linhas e as duas
-- médias sairiam iguais, legitimamente. Cobrar 60/60 seria congelar o dado de hoje como se fosse
-- regra — o mesmo erro que esta task existe para não cometer.
--
-- ⚠️ A COBRANÇA É POR (UNIVERSO × CÉLULA) DESDE A #58. O comportamento das duas contagens é
-- propriedade do RECORTE da célula e vale em qualquer universo, então generalizar custou uma
-- coluna no GROUP BY e multiplicou por quatro o que é conferido. E fechou um buraco: cobrada só
-- sobre a tabela inteira, a ponta `ultimos_10_sem_teto` ficaria verde por uma célula com teto num
-- universo só, mesmo que nos outros três o carimbo tivesse rodado fora de ordem.
--
-- ⚠️ NÃO É A MESMA CONFERÊNCIA DA `analyses/taskf_saturacao_recorte.sql`, e as duas não se
-- substituem. Aquela mede a identidade `usado = LEAST(disponível, 10)` PAR A PAR, nos 21.054
-- pares de (jogo, time) do carimbo do PIT; esta cobra o comportamento das duas colunas na tabela
-- do ENTREGÁVEL, que é o artefato que a [B] vai ler. Um erro na agregação do Teste 2 — a média
-- lendo a coluna errada, por exemplo — passa incólume pela primeira e cai nesta.
--
-- QUEM RODA: a FASE 3 da receita do analyses/taskf_teste2.sql, depois das quatro células —
-- `dbt test --target taskF --select tag:costura_b`. Não é o agendado (tag `guarda`).
--
-- Falsificada de propósito trocando o `pit_recorte` de uma célula (e desfazendo em seguida); os
-- comandos e o resultado estão em `docs/TASKF_RESULTADOS.md`, seção do ticket #55.

WITH por_celula AS (
    SELECT
        universo,
        celula,
        ANY_VALUE(pit_recorte) AS pit_recorte,
        COUNT(*)               AS linhas,
        COUNTIF(jogos_medios_disp IS DISTINCT FROM jogos_medios_usado) AS linhas_com_teto,
        COUNT(DISTINCT pit_recorte) AS recortes_na_celula
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    GROUP BY universo, celula
),

divergencias AS (
    SELECT
        CASE
            WHEN pit_recorte = 'temporada'  THEN 'temporada_com_teto'
            WHEN pit_recorte = 'ultimos_10' THEN 'ultimos_10_sem_teto'
            ELSE                                 'recorte_desconhecido'
        END AS motivo,
        TO_JSON_STRING(STRUCT(
            universo, celula, pit_recorte, linhas, linhas_com_teto, recortes_na_celula
        )) AS linha
    FROM por_celula
    WHERE (pit_recorte = 'temporada'  AND linhas_com_teto > 0)
       OR (pit_recorte = 'ultimos_10' AND linhas_com_teto = 0)
       OR  pit_recorte NOT IN ('temporada', 'ultimos_10')
       OR  recortes_na_celula <> 1
),

-- O detalhe das linhas que quebraram o lado `temporada`, que é o caso em que saber QUAL linha
-- diverge é o começo da investigação. No outro lado não há linha para mostrar: o defeito é a
-- ausência delas.
detalhe AS (
    SELECT
        'temporada_com_teto_detalhe' AS motivo,
        TO_JSON_STRING(STRUCT(
            t.universo, t.celula, t.mercado, t.premissa, t.benchmark,
            t.jogos_medios_disp, t.jogos_medios_usado
        )) AS linha
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2` AS t
    JOIN por_celula AS c USING (universo, celula)
    WHERE c.pit_recorte = 'temporada'
      AND t.jogos_medios_disp IS DISTINCT FROM t.jogos_medios_usado
)

SELECT motivo, linha FROM divergencias
UNION ALL
SELECT motivo, linha FROM detalhe