{#
    Task [E] — Achados colaterais da [0.1], item 1 (ClickUp `wdx6zevnj0`).

    A pergunta: o backtest de `task01_base()` era mais permissivo que o board — media
    aposta que o produto recusa. Decisão do Victor em 2026-09-10: aplicar os mesmos
    gates do board, para que este número deixe de circular como se fosse o do produto.

    QUAL GATE. A task original citava "n_casas >= 4 e completude do conjunto Pinnacle".
    O Victor corrigiu: "completude" não é gate do board hoje (dado faltante diagnostica,
    ADR 0003), e a "porta de premissas: 2+ acesas com peso > 0" que ele citou também não
    está em `passou_no_gate` — conferido em `fact_value_funnel.sql` antes de implementar.
    Os gates que O BOARD REALMENTE APLICA são as três portas de preço da [A3+A5] (#104),
    em vigor desde a virada (#109): `porta_liquidez_estrita` (n_casas >= 4),
    `porta_outlier` (NOT pen_odd_outlier) e `porta_faixa_odd` (best_odd na faixa do
    mercado). Foram essas três que entraram como WHERE em `task01_base()` — ver o ⚠️
    "GATES DO BOARD" no macro.

    SEM GATES é o universo que existia antes desta entrega: mesmo escopo de mercado e
    meia-linha, sem as três portas de preço. Está aqui só para o antes/depois não
    desaparecer da história — não é mais o número que qualquer análise nova deveria
    reportar.

    Rodar com:
      dbt compile --select task01_gates_board
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_gates_board.sql
#}

WITH {{ task01_base() }},

sem_gates AS (
    -- Reconstrói o universo pré-2026-09-10: mesmo escopo/meia-linha de `apostas`, sem
    -- as três portas de preço que agora estão no WHERE do macro. Lê `odds` direto
    -- (que não passa pelas portas) e repete só o recorte que `apostas` já fazia antes.
    SELECT
        o.market_id,
        o.fixture_id,
        o.best_odd,
        {{ task01_liquidacao('o.', 'j.') }} AS ganhou
    FROM odds AS o
    JOIN jogos_encerrados AS j
      ON j.fixture_id = o.fixture_id
    JOIN prem_n AS pn
      ON  pn.market_id                  = o.market_id
      AND pn.fixture_id                 = o.fixture_id
      AND pn.outcome_side               = o.outcome_side
      AND COALESCE(pn.line_value, -999) = COALESCE(o.line_value, -999)
    WHERE o.best_odd IS NOT NULL
      AND o.edge     IS NOT NULL
      AND o.market_id IN ({{ task01_markets().keys() | join(', ') }})
      AND {{ task01_meia_linha('o.') }}
),

comparacao AS (
    SELECT
        'a. sem gates de preco (universo pre-2026-09-10)' AS corte,
        COUNT(*)                                                    AS n_linhas,
        ROUND(100.0 * SUM(best_odd * CAST(ganhou AS INT64) - 1) / COUNT(*), 1) AS roi_pct
    FROM sem_gates

    UNION ALL

    SELECT
        'b. com os gates do board (liquidez + outlier + faixa de odd)' AS corte,
        COUNT(*)                                                    AS n_linhas,
        ROUND(100.0 * SUM(best_odd * CAST(ganhou AS INT64) - 1) / COUNT(*), 1) AS roi_pct
    FROM apostas
)

SELECT * FROM comparacao ORDER BY corte
