{#
    Task [0.1] — TESTE 1 completo na base limpa.  Ticket #6, spec #3.

    O Teste 1 mede se a premissa PREVÊ O RESULTADO DA LINHA:

        diferença = média(acerto | premissa acesa) − média(taxa base da MESMA linha)

    onde "taxa base da mesma linha" é o acerto médio de todas as linhas do mesmo
    (mercado, lado, valor da linha) — o Over 2.5 de uma premissa é comparado ao Over 2.5
    em geral, não ao universo inteiro.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ELE EXISTE AQUI, e por que NÃO é a fonte primária de peso:

    Prever a linha não é gerar valor. Uma premissa pode acertar muito e não pagar nada,
    porque o mercado também sabe — foi essa distinção que primeiro salvou e depois
    derrubou o `xg_combinado_alto`. Quem define peso é o Teste 2.

    O Teste 1 entra como CONTROLE OUT-OF-SAMPLE exigido pelo ADR 0001: ele não precisa
    de odd, então roda em todo jogo encerrado — um universo de milhares de partidas,
    DISJUNTO das ~170 em que o ROI do Teste 4 é medido. Pesos vindos daqui são ajustados
    em dados que não são os dados avaliados, e é isso que faz deles um controle.
    ────────────────────────────────────────────────────────────────────────────────
    O universo é construído do `prem_long` + `jogos_encerrados` do macro, com a MESMA
    liquidação e o MESMO filtro de meia-linha do Teste 2/3 (macros `task01_liquidacao` e
    `task01_meia_linha`). Nada é redefinido localmente: se as duas medições liquidassem
    diferente, a comparação entre elas não significaria nada.

    O piso de amostra entra como coluna pelo mesmo motivo do Teste 2 — lá ele INVERTEU
    os três maiores sinais. Um peso de controle medido sem piso carregaria o mesmo
    artefato que o peso primário, e deixaria de ser controle de coisa alguma.

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_teste1
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_teste1.sql
#}

WITH {{ task01_base() }},

{#- Universo do Teste 1: toda linha de premissa de jogo encerrado, COM OU SEM ODD. É
    aqui que ele se separa do Teste 2 — e é essa separação que o torna um controle. -#}
linhas AS (
    SELECT
        pl.market_id,
        pl.fixture_id,
        pl.outcome_side,
        pl.line_value,
        pl.premissa,
        pl.acesa,
        j.season,
        COALESCE(pit.min_jogos, 0)          AS min_jogos,
        {{ task01_liquidacao('pl.', 'j.') }} AS ganhou
    FROM prem_long AS pl
    JOIN jogos_encerrados AS j
      ON j.fixture_id = pl.fixture_id
    LEFT JOIN pit
      ON pit.fixture_id = pl.fixture_id
    WHERE {{ task01_meia_linha('pl.') }}
),

{#- Taxa base por (mercado, lado, linha). Deduplicado ao grão de LINHA antes de agregar:
    `linhas` tem uma tupla por premissa, e agregar direto ali pesaria cada linha pelo
    número de premissas do mercado. -#}
linhas_unicas AS (
    SELECT DISTINCT market_id, fixture_id, outcome_side, line_value, ganhou
    FROM linhas
),
base_linha AS (
    SELECT
        market_id,
        outcome_side,
        line_value,
        AVG(CAST(ganhou AS INT64)) AS taxa_base,
        COUNT(*)                   AS n_linha
    FROM linhas_unicas
    GROUP BY 1, 2, 3
),

universo AS (
    SELECT
        COUNT(DISTINCT fixture_id)                                          AS jogos,
        COUNT(DISTINCT IF(season = 2024, fixture_id, NULL))                 AS jogos_2024,
        COUNT(DISTINCT IF(season = 2025, fixture_id, NULL))                 AS jogos_2025,
        COUNT(DISTINCT IF(season = 2026, fixture_id, NULL))                 AS jogos_2026
    FROM linhas
),

agregado AS (
    SELECT
        l.market_id,
        l.premissa,
        AVG(IF(l.acesa, l.min_jogos, NULL))                     AS jogos_medios,
        AVG(IF(l.acesa, IF(l.min_jogos < 5, 1.0, 0.0), NULL))   AS frac_curta
        {%- for piso in [0, 5, 10] %},
        COUNTIF(l.acesa AND l.min_jogos >= {{ piso }})          AS n_{{ piso }},
        AVG(IF(l.acesa AND l.min_jogos >= {{ piso }},
               CAST(l.ganhou AS INT64), NULL))                  AS p_real_{{ piso }},
        AVG(IF(l.acesa AND l.min_jogos >= {{ piso }},
               b.taxa_base, NULL))                              AS p_base_{{ piso }}
        {%- endfor %}
    FROM linhas AS l
    JOIN base_linha AS b
      ON  b.market_id                  = l.market_id
      AND b.outcome_side               = l.outcome_side
      AND COALESCE(b.line_value, -999) = COALESCE(l.line_value, -999)
    GROUP BY l.market_id, l.premissa
    HAVING COUNTIF(l.acesa) > 0
)

SELECT
    u.jogos                                                 AS jogos_no_universo,
    u.jogos_2024,
    u.jogos_2025,
    u.jogos_2026,
    CASE g.market_id
        {%- for mid, m in task01_markets().items() %}
        WHEN {{ mid }} THEN '{{ m.nome }}'
        {%- endfor %}
    END                                                     AS mercado,
    g.premissa,
    ROUND(SAFE_DIVIDE(g.n_0, g.n_0 + 50), 2)                AS fator_encolhimento,
    ROUND(g.jogos_medios, 1)                                AS jogos_medios,
    ROUND(g.frac_curta * 100, 1)                            AS pct_amostra_curta
    {%- for piso in [0, 5, 10] %},
    g.n_{{ piso }}                                          AS n_p{{ piso }},
    ROUND(g.p_base_{{ piso }} * 100, 1)                     AS taxa_base_p{{ piso }},
    ROUND(g.p_real_{{ piso }} * 100, 1)                     AS acertou_p{{ piso }},
    ROUND((g.p_real_{{ piso }} - g.p_base_{{ piso }}) * 100, 1) AS diferenca_p{{ piso }},
    -- Peso de CONTROLE, mesma regra de encolhimento do Teste 2 p/ que as duas fontes
    -- sejam comparáveis entre si: max(diferença, 0) × n/(n+50).
    ROUND(GREATEST((g.p_real_{{ piso }} - g.p_base_{{ piso }}) * 100, 0)
          * SAFE_DIVIDE(g.n_{{ piso }}, g.n_{{ piso }} + 50), 2) AS peso_ctrl_p{{ piso }}
    {%- endfor %}
FROM agregado AS g
CROSS JOIN universo AS u
ORDER BY mercado, diferenca_p0 DESC
