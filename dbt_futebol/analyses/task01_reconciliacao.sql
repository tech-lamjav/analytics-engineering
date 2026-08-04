{#
    Task [0.1] — SEAM 1: reconciliação por resposta conhecida.  Ticket #4, spec #3.

    Roda a máquina GENERALIZADA (`task01_base`) restrita ao escopo que já foi publicado
    e mostra esperado vs obtido. Verde significa duas coisas, e as duas são necessárias
    antes de qualquer análise a jusante:

      1. generalizar para os 5 mercados não quebrou a lógica de gate nem de liquidação;
      2. as tabelas de premissa e odds são ESTÁVEIS entre rebuilds — nunca verificado,
         e toda conclusão histórica depende disso.

    Divergência não é necessariamente bug: pode ser instabilidade de tabela. As duas
    hipóteses são separáveis pelo `n` que vai ao lado de cada linha — valor diferente
    com amostra igual é lógica; amostra diferente é universo.

    Corte congelado em 2026-08-02, que é a janela dos números publicados (16/06 a 02/08).

    ────────────────────────────────────────────────────────────────────────────────
    RESULTADO DA PRIMEIRA EXECUÇÃO (2026-08-04) — a máquina está certa, a base não é
    estável:

      · 22 das 25 linhas com delta EXATAMENTE 0,0, incluindo as 6 do Teste 2 e 4 dos 5
        mercados (Dupla Chance inclusive bate o n=154 publicado).
      · Só o mercado de GOLS derivou: −6,9 contra −7,3 publicado. A deriva agregada dos
        cortes 2+/3+ é inteiramente explicada por ele (Gols é 2.182 das 4.066 apostas).
      · Confirmado que não é regressão da generalização: a query ad-hoc original, rodada
        hoje sem alterar um byte, também devolve −7,4 onde ontem devolveu −7,6.

    CAUSA: o Gols é o ÚNICO dos 5 mercados com premissa derivada de odd. `linha_subindo`
    e `linha_descendo` leem `fact_odds_snapshot` direto (média das probabilidades
    implícitas de todas as casas, t24h -> t15m), e o modelo ainda monta o universo de
    linhas a partir das odds presentes. Toda vez que a tabela de odds muda, essas duas
    premissas podem virar, `n_prem` muda e o ROI dos cortes por contagem muda junto.
    1X2, Handicap, BTTS e Dupla Chance não leem odd em premissa nenhuma — e são
    exatamente os quatro que reproduziram byte a byte.

    MEDIDO, contra o snapshot congelado `futebol_task0` (as duas premissas de linha "já
    eram limpas" na Task 0, logo o `_before` guarda o valor de ontem):

        linha_descendo                       20 flips / 50.608 linhas
        linha_subindo                        16 flips / 50.608 linhas
        historico_over    (controle limpo)    0 flips
        historico_under   (controle limpo)    0 flips

    O controle fecha o argumento: `historico_over/under` estão na MESMA classe de
    premissa não afetada pela correção da Task 0, mas leem histórico em vez de odd — e
    não mexeram uma linha.

    CONSEQUÊNCIA p/ os tickets a jusante:

      1. Número de Gols só é comparável entre execuções se a data de build for
         registrada junto. Todo relatório desta task precisa carimbar o `dbt_loaded_at`
         das tabelas de origem.
      2. 0,07% das linhas viraram e isso moveu o ROI do mercado em 0,4pp — porque a
         porta é um LIMIAR: uma linha que vai de n_prem=1 p/ 2 entra inteira no
         universo. Vale checar no Teste 4 se a nota ponderada, sendo contínua, é menos
         sensível a esse ruído que a porta de contagem. Se for, é um argumento a favor
         dela que ninguém levantou ainda — e que não depende do resultado de ROI.
    ────────────────────────────────────────────────────────────────────────────────

    Rodar com:
      dbt compile --select path:analyses/task01_reconciliacao.sql
      e executar o SQL de target/compiled/... no BigQuery
#}

WITH {{ task01_base(cutoff='2026-08-02') }},

-- Teste 3: ROI de cada porta, stake fixa na melhor odd.
teste3 AS (
    SELECT 'Teste 3' AS bloco, 'a. universo sem porta' AS metrica,
           COUNT(*) AS n, -10.2 AS esperado,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM bets

    UNION ALL
    SELECT 'Teste 3', 'b. 2+ premissas',
           COUNT(*), -7.6,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM bets WHERE n_prem >= 2

    UNION ALL
    SELECT 'Teste 3', 'c. 3+ premissas',
           COUNT(*), -6.0,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM bets WHERE n_prem >= 3

    UNION ALL
    SELECT 'Teste 3', 'd. regra de hoje (edge > 0)',
           COUNT(*), -12.3,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM bets WHERE edge > 0

    UNION ALL
    SELECT 'Teste 3', 'e. edge > 0 e 2+ premissas',
           COUNT(*), -15.4,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM bets WHERE edge > 0 AND n_prem >= 2
),

-- Teste 3 por mercado, na porta "2+ premissas". Localiza a deriva: se só um mercado
-- se mover, a instabilidade tem endereço.
teste3_mercado AS (
    SELECT
        'Teste 3 por mercado (2+)' AS bloco,
        CASE b.market_id
            WHEN 1  THEN 'a. 1X2'
            WHEN 5  THEN 'b. Gols'
            WHEN 4  THEN 'c. Handicap'
            WHEN 8  THEN 'd. BTTS'
            WHEN 12 THEN 'e. Dupla Chance'
        END AS metrica,
        COUNT(*) AS n,
        ANY_VALUE(m.esperado) AS esperado,
        ROUND((SUM(IF(b.ganhou, b.best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM bets AS b
    JOIN UNNEST([
        STRUCT(1  AS market_id, -2.5 AS esperado),
        STRUCT(5  AS market_id, -7.3 AS esperado),
        STRUCT(4  AS market_id, -9.9 AS esperado),
        STRUCT(8  AS market_id, -1.1 AS esperado),
        STRUCT(12 AS market_id,  1.4 AS esperado)
    ]) AS m
      ON m.market_id = b.market_id
    WHERE b.n_prem >= 2
    GROUP BY b.market_id
),

-- Teste 2 do mercado de Gols, contra benchmark sharp (o mesmo filtro da rodada
-- anterior, que exigia valor_fonte='pinnacle'). Métrica: acerto médio menos prob justa
-- média, nas linhas em que a premissa acendeu.
teste2_gols AS (
    SELECT
        'Teste 2 (Gols)' AS bloco,
        pl.premissa      AS metrica,
        COUNTIF(pl.acesa) AS n,
        e.esperado,
        ROUND((AVG(IF(pl.acesa, CAST(b.ganhou AS INT64), NULL))
             - AVG(IF(pl.acesa, b.prob_justa_fechamento, NULL))) * 100, 1) AS obtido
    FROM bets AS b
    JOIN prem_long AS pl
      ON  pl.market_id                  = b.market_id
      AND pl.fixture_id                 = b.fixture_id
      AND pl.outcome_side               = b.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(b.line_value, -999)
    JOIN UNNEST([
        STRUCT('clean_sheets_altos' AS premissa,  16.9 AS esperado),
        STRUCT('defesas_firmes'     AS premissa,   3.4 AS esperado),
        STRUCT('xg_combinado_alto'  AS premissa,  -2.6 AS esperado),
        STRUCT('ataque_combinado'   AS premissa,  -3.6 AS esperado),
        STRUCT('defesas_vazaveis'   AS premissa,  -5.2 AS esperado),
        STRUCT('ambos_vazam'        AS premissa,  -3.7 AS esperado)
    ]) AS e
      ON e.premissa = pl.premissa
    WHERE b.market_id = 5
      AND b.benchmark = 'sharp'
    GROUP BY 1, 2, 4
),

cobertura AS (
    SELECT 'Cobertura' AS bloco, 'a. jogos com odd' AS metrica,
           COUNT(*) AS n, 168.0 AS esperado,
           CAST(COUNT(DISTINCT fixture_id) AS FLOAT64) AS obtido
    FROM bets

    -- Se isto não for zero, a degradação graciosa falhou em algum lugar: contar
    -- premissas por SUM(CAST(bool AS INT64)) (a query original) propaga NULL e derruba
    -- a linha inteira de toda porta, enquanto COUNTIF não. Aí o número publicado não é
    -- reproduzível por construção, e não por erro meu.
    UNION ALL
    SELECT 'Cobertura', 'b. linhas com premissa NULL',
           COUNT(*), 0.0,
           CAST(SUM(n_prem_null) AS FLOAT64)
    FROM bets
),

-- Informativo: onde procurar, se algo acima divergir. Sem valor publicado p/ comparar.
-- Agrupa POR benchmark, não ANY_VALUE(benchmark): os mercados 4 e 5 são MISTOS (a
-- Pinnacle cobre a maior parte, mas não todos os jogos), e um rótulo arbitrário por
-- mercado esconderia exatamente a distinção que a task existe para tornar visível.
por_mercado AS (
    SELECT
        'Cobertura por benchmark' AS bloco,
        CONCAT('market ', CAST(market_id AS STRING), ' — ', benchmark) AS metrica,
        COUNT(*) AS n,
        CAST(NULL AS FLOAT64) AS esperado,
        ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM bets
    GROUP BY market_id, benchmark
)

SELECT
    bloco,
    metrica,
    n,
    esperado,
    obtido,
    ROUND(obtido - esperado, 1) AS delta,
    CASE
        WHEN esperado IS NULL                        THEN '—'
        WHEN ABS(obtido - esperado) < 0.05           THEN 'OK'
        WHEN ABS(obtido - esperado) <= 0.3           THEN 'ATENCAO'
        ELSE                                              'DIVERGE'
    END AS status
FROM (
    SELECT * FROM teste3
    UNION ALL SELECT * FROM teste3_mercado
    UNION ALL SELECT * FROM teste2_gols
    UNION ALL SELECT * FROM cobertura
    UNION ALL SELECT * FROM por_mercado
)
ORDER BY bloco, metrica
