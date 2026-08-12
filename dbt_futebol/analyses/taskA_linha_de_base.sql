{#
    LINHA DE BASE DO BOARD — entregável de aceite da task [A].

    "Uma query mostrando, no board de hoje, quantas oportunidades cada porta remove,
    separadamente. Serve de linha de base."

    Reproduz os 5 ramos do `fact_value_opportunities` SEM gate nenhum e depois mede, sobre
    esse universo, o efeito de cada porta — a de hoje e a proposta — em duas leituras:

      isolado     quantas linhas ESTA porta sozinha removeria do universo bruto.
                  As somas se sobrepõem: uma linha pode falhar em três portas.
      marginal    quantas linhas ESTA porta remove depois das anteriores da fila.
                  As somas fecham, e é esta que diz o que cada porta ainda acrescenta.

    ESCOPO: duas janelas, porque "o board de hoje" pode ter poucas partidas e a leitura
    ficar refém do dia.
      a. board_atual   fixtures que ainda não começaram (o board de verdade).
      b. ultimos_30d   fixtures com kickoff nos últimos 30 dias (volume p/ estabilizar).

    ⚠ A nota nova é `clamp(pts_premissas − penalidades de contexto, 0) / teto × 100`, com
    TETO POR MERCADO E POR LADO — os tetos abaixo saem da leitura dos modelos de premissa
    e são a mesma tabela da seção D2 da spec. Se um peso mudar lá, muda aqui.

    ⚠ A variante `sem_mov_linha` tira `linha_subindo`/`linha_descendo` (6 pts cada, Gols),
    que leem movimento de odd. É a decisão D1 da spec, ainda pendente de confirmação —
    por isso as duas notas saem lado a lado em vez de uma escolhida.

    Rodar com:
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_linha_de_base
      bq query --use_legacy_sql=false < ../target/compiled/dbt_futebol/analyses/taskA_linha_de_base.sql
#}

WITH fixtures AS (
    SELECT
        fixture_id,
        CASE
            WHEN kickoff_utc > CURRENT_TIMESTAMP()                                  THEN 'a. board_atual'
            WHEN DATE(kickoff_utc) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)      THEN 'b. ultimos_30d'
        END AS escopo
    FROM {{ ref('fact_fixtures') }}
),
board AS (
    SELECT fixture_id, escopo FROM fixtures WHERE escopo IS NOT NULL
),

{#- REDUZIDO À JANELA CORRENTE (#37): sem isso o funil conta a mesma candidata uma vez
    por janela e infla em até 4×. É a armadilha que a própria A7 nomeia como a mais
    importante do seu aceite — "fixar uma janela por candidato ANTES de contar qualquer
    coisa". Reduzindo aqui, esta linha de base segue comparável com a que produziu o
    dimensionamento de 50 -> 689 linhas. -#}
devig AS (
    SELECT *, COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM ({{ futebol_devig_janela_corrente() }})
),
corro AS (
    SELECT *, COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM {{ ref('int_futebol_corroboracao') }}
),

{#- ─────────────────────────────────────────────────────────────────────────────────
    Os 5 ramos, SEM gate. Cada um devolve o mesmo shape: pontos, penalidade de contexto,
    teto do lado, e o bloco de odds. `pen_contexto` é a penalidade específica do mercado
    (as de odd saem da nota por decisão da task, então não entram aqui).
    ───────────────────────────────────────────────────────────────────────────────── -#}
ramo_1x2 AS (
    SELECT
        b.escopo, p.fixture_id, 'match_winner' AS market, p.outcome,
        CAST(NULL AS FLOAT64) AS line_value,
        p.pts_premissas,
        p.pts_premissas                                   AS pts_sem_mov,
        p.penalidades_1x2_pts                             AS pen_contexto,
        {#- Home alcança pts_mando=8; Away só 4; Draw não tem lado apostado -> nada dispara. -#}
        CASE p.outcome WHEN 'Home' THEN 51 WHEN 'Away' THEN 47 ELSE 0 END AS teto,
        CASE p.outcome WHEN 'Home' THEN 51 WHEN 'Away' THEN 47 ELSE 0 END AS teto_sem_mov,
        d.pts_valor, d.penalidades_globais_pts, d.pen_odd_outlier,
        d.best_odd, d.n_casas, d.prob_justa_fechamento, d.valor_fonte, d.edge,
        COALESCE(c.pts_corroboracao, 0) AS pts_corroboracao,
        COALESCE(d.pin_n_outcomes >= 3, FALSE)            AS passa_completude,
        TRUE                                              AS passa_meia_linha
    FROM {{ ref('int_futebol_premissas_1x2') }} p
    JOIN board b        ON b.fixture_id = p.fixture_id
    JOIN devig d        ON d.market_id = 1 AND d.fixture_id = p.fixture_id AND d.outcome_side = p.outcome
    LEFT JOIN corro c   ON c.market_id = 1 AND c.fixture_id = p.fixture_id AND c.outcome_side = p.outcome
),

ramo_ou AS (
    SELECT
        b.escopo, p.fixture_id, 'goals_over_under' AS market, p.outcome,
        p.line_value,
        p.pts_premissas,
        {#- D1: sem as duas premissas que leem movimento de odd (6 pts cada). -#}
        p.pts_premissas - 6 * CAST(p.linha_subindo AS INT64) - 6 * CAST(p.linha_descendo AS INT64) AS pts_sem_mov,
        p.penalidades_ou_pts                              AS pen_contexto,
        IF(p.outcome = 'Over', 56, 52)                    AS teto,
        IF(p.outcome = 'Over', 50, 46)                    AS teto_sem_mov,
        d.pts_valor, d.penalidades_globais_pts, d.pen_odd_outlier,
        d.best_odd, d.n_casas, d.prob_justa_fechamento, d.valor_fonte, d.edge,
        COALESCE(c.pts_corroboracao, 0) AS pts_corroboracao,
        COALESCE(d.pin_n_outcomes >= 2, FALSE)            AS passa_completude,
        COALESCE(MOD(CAST(ROUND(ABS(p.line_value) * 2) AS INT64), 2) = 1, FALSE) AS passa_meia_linha
    FROM {{ ref('int_futebol_premissas_ou') }} p
    JOIN board b        ON b.fixture_id = p.fixture_id
    JOIN devig d        ON d.market_id = 5 AND d.fixture_id = p.fixture_id AND d.outcome_side = p.outcome
                       AND d.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
    LEFT JOIN corro c   ON c.market_id = 5 AND c.fixture_id = p.fixture_id AND c.outcome_side = p.outcome
                       AND c.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
),

ramo_ah AS (
    SELECT
        b.escopo, p.fixture_id, 'asian_handicap' AS market, p.outcome,
        p.line_value,
        p.pts_premissas,
        p.pts_premissas                                   AS pts_sem_mov,
        p.penalidades_ah_pts                              AS pen_contexto,
        {#- line_value vem na ótica do mandante; o handicap DO LADO é o oposto p/ o visitante.
            <0 = favorito (Σ40) · >0 = azarão (Σ30) · =0 = pick (nada dispara). -#}
        CASE
            WHEN IF(p.outcome = 'Home', p.line_value, -p.line_value) < 0 THEN 40
            WHEN IF(p.outcome = 'Home', p.line_value, -p.line_value) > 0 THEN 30
            ELSE 0
        END                                               AS teto,
        CASE
            WHEN IF(p.outcome = 'Home', p.line_value, -p.line_value) < 0 THEN 40
            WHEN IF(p.outcome = 'Home', p.line_value, -p.line_value) > 0 THEN 30
            ELSE 0
        END                                               AS teto_sem_mov,
        d.pts_valor, d.penalidades_globais_pts, d.pen_odd_outlier,
        d.best_odd, d.n_casas, d.prob_justa_fechamento, d.valor_fonte, d.edge,
        COALESCE(c.pts_corroboracao, 0) AS pts_corroboracao,
        COALESCE(d.pin_n_outcomes >= 2, FALSE)            AS passa_completude,
        COALESCE(MOD(CAST(ROUND(ABS(p.line_value) * 2) AS INT64), 2) = 1, FALSE) AS passa_meia_linha
    FROM {{ ref('int_futebol_premissas_ah') }} p
    JOIN board b        ON b.fixture_id = p.fixture_id
    JOIN devig d        ON d.market_id = 4 AND d.fixture_id = p.fixture_id AND d.outcome_side = p.outcome
                       AND d.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
    LEFT JOIN corro c   ON c.market_id = 4 AND c.fixture_id = p.fixture_id AND c.outcome_side = p.outcome
                       AND c.line_key = COALESCE(CAST(p.line_value AS STRING), 'NONE')
),

ramo_btts AS (
    SELECT
        b.escopo, p.fixture_id, 'btts' AS market, p.outcome,
        CAST(NULL AS FLOAT64) AS line_value,
        p.pts_premissas,
        p.pts_premissas                                   AS pts_sem_mov,
        p.penalidades_btts_pts                            AS pen_contexto,
        IF(p.outcome = 'Yes', 34, 28)                     AS teto,
        IF(p.outcome = 'Yes', 34, 28)                     AS teto_sem_mov,
        d.pts_valor, d.penalidades_globais_pts, d.pen_odd_outlier,
        d.best_odd, d.n_casas, d.prob_justa_fechamento, d.valor_fonte, d.edge,
        COALESCE(c.pts_corroboracao, 0) AS pts_corroboracao,
        COALESCE(d.n_outcomes_valor >= 2, FALSE)          AS passa_completude,
        TRUE                                              AS passa_meia_linha
    FROM {{ ref('int_futebol_premissas_btts') }} p
    JOIN board b        ON b.fixture_id = p.fixture_id
    JOIN devig d        ON d.market_id = 8 AND d.fixture_id = p.fixture_id AND d.outcome_side = p.outcome
    LEFT JOIN corro c   ON c.market_id = 8 AND c.fixture_id = p.fixture_id AND c.outcome_side = p.outcome
),

ramo_dc AS (
    SELECT
        b.escopo, p.fixture_id, 'double_chance' AS market, p.outcome,
        CAST(NULL AS FLOAT64) AS line_value,
        p.pts_premissas,
        p.pts_premissas                                   AS pts_sem_mov,
        0                                                 AS pen_contexto,
        34                                                AS teto,
        34                                                AS teto_sem_mov,
        d.pts_valor, d.penalidades_globais_pts, d.pen_odd_outlier,
        d.best_odd, d.n_casas, d.prob_justa_fechamento, d.valor_fonte, d.edge,
        COALESCE(c.pts_corroboracao, 0) AS pts_corroboracao,
        COALESCE(d.n_outcomes_valor >= 3, FALSE)          AS passa_completude,
        TRUE                                              AS passa_meia_linha
    FROM {{ ref('int_futebol_premissas_dc') }} p
    JOIN board b        ON b.fixture_id = p.fixture_id
    JOIN devig d        ON d.market_id = 12 AND d.fixture_id = p.fixture_id AND d.outcome_side = p.outcome
    LEFT JOIN corro c   ON c.market_id = 12 AND c.fixture_id = p.fixture_id AND c.outcome_side = p.outcome
),

universo AS (
    SELECT * FROM ramo_1x2
    UNION ALL SELECT * FROM ramo_ou
    UNION ALL SELECT * FROM ramo_ah
    UNION ALL SELECT * FROM ramo_btts
    UNION ALL SELECT * FROM ramo_dc
),

notas AS (
    SELECT
        *,
        {#- Score de HOJE, p/ contraste. -#}
        LEAST(GREATEST(pts_valor + pts_premissas + pts_corroboracao
                       - penalidades_globais_pts - pen_contexto, 0), 100)          AS score_hoje,
        {#- Nota NOVA: só contexto, normalizada pelo teto do lado. Teto 0 (empate, pick de
            handicap) devolve 0 em vez de erro — é a guarda da D3 da spec. -#}
        CAST(ROUND(COALESCE(SAFE_DIVIDE(GREATEST(pts_premissas - pen_contexto, 0), teto), 0) * 100) AS INT64) AS nota,
        CAST(ROUND(COALESCE(SAFE_DIVIDE(GREATEST(pts_sem_mov  - pen_contexto, 0), teto_sem_mov), 0) * 100) AS INT64) AS nota_sem_mov,
        {#- Faixa de odd por mercado (A5). -#}
        IF(market = 'double_chance', 1.25, 1.50)                                   AS odd_min,
        IF(market = 'double_chance', 2.00, 4.00)                                   AS odd_max
    FROM universo
),

portas AS (
    SELECT
        escopo, market, fixture_id, outcome, line_value, valor_fonte,
        edge, best_odd, n_casas, score_hoje, nota, nota_sem_mov,

        {#- ── Portas estruturais, iguais nos dois regimes ── -#}
        (prob_justa_fechamento IS NOT NULL) AS p0_devig,
        passa_completude                    AS p1_completude,
        passa_meia_linha                    AS p2_meia_linha,

        {#- ── Regime de HOJE ── -#}
        (n_casas >= 3)                                                    AS h1_casas3,
        (edge > IF(valor_fonte = 'consenso', 0.03, 0))                    AS h2_edge,
        (score_hoje >= 40)                                                AS h3_score40,

        {#- ── Regime NOVO ── -#}
        (n_casas >= 4)                                                    AS n1_casas4,
        (NOT pen_odd_outlier)                                             AS n2_outlier,
        (best_odd BETWEEN odd_min AND odd_max)                            AS n3_faixa_odd,
        (nota >= 40)                                                      AS n4_nota40,
        (valor_fonte <> 'consenso' OR nota >= 50)                         AS n5_consenso50,
        (nota_sem_mov >= 40)                                              AS n4b_nota40_sem_mov,
        (valor_fonte <> 'consenso' OR nota_sem_mov >= 50)                 AS n5b_consenso50_sem_mov
    FROM notas
),

{#- Cumulativo em ordem de fila, p/ a leitura MARGINAL. Cada `cum_k` é "passou em todas
    até aqui". A porta k remove (cum_{k-1} AND NOT passa_k). -#}
cum AS (
    SELECT
        *,
        p0_devig AND p1_completude AND p2_meia_linha                                   AS cum_estrutural,
        p0_devig AND p1_completude AND p2_meia_linha AND h1_casas3                     AS cum_h1,
        p0_devig AND p1_completude AND p2_meia_linha AND h1_casas3 AND h2_edge         AS cum_h2,
        p0_devig AND p1_completude AND p2_meia_linha AND h1_casas3 AND h2_edge AND h3_score40 AS cum_h3,
        p0_devig AND p1_completude AND p2_meia_linha AND n1_casas4                     AS cum_n1,
        p0_devig AND p1_completude AND p2_meia_linha AND n1_casas4 AND n2_outlier      AS cum_n2,
        p0_devig AND p1_completude AND p2_meia_linha AND n1_casas4 AND n2_outlier AND n3_faixa_odd AS cum_n3,
        p0_devig AND p1_completude AND p2_meia_linha AND n1_casas4 AND n2_outlier AND n3_faixa_odd AND n4_nota40 AS cum_n4,
        p0_devig AND p1_completude AND p2_meia_linha AND n1_casas4 AND n2_outlier AND n3_faixa_odd AND n4_nota40 AND n5_consenso50 AS cum_n5,
        p0_devig AND p1_completude AND p2_meia_linha AND n1_casas4 AND n2_outlier AND n3_faixa_odd AND n4b_nota40_sem_mov AND n5b_consenso50_sem_mov AS cum_n5_sem_mov
    FROM portas
),

funil AS (
    SELECT escopo, market, f.*
    FROM cum
    CROSS JOIN UNNEST([
        STRUCT('00. universo bruto'        AS porta, 'ambos'  AS regime, TRUE AS entrou, TRUE  AS passou),
        STRUCT('01. de-vig válido',                  'ambos',  TRUE,                    p0_devig),
        STRUCT('02. completude do conjunto',         'ambos',  p0_devig,                p0_devig AND p1_completude),
        STRUCT('03. linha meia (AH/Gols)',           'ambos',  p0_devig AND p1_completude, cum_estrutural),

        STRUCT('10. liquidez >= 3 casas',            'hoje',   cum_estrutural,          cum_h1),
        STRUCT('11. edge positivo',                  'hoje',   cum_h1,                  cum_h2),
        STRUCT('12. score antigo >= 40',             'hoje',   cum_h2,                  cum_h3),

        STRUCT('20. liquidez >= 4 casas',            'novo',   cum_estrutural,          cum_n1),
        STRUCT('21. odd fora da curva',              'novo',   cum_n1,                  cum_n2),
        STRUCT('22. faixa de odd do mercado',        'novo',   cum_n2,                  cum_n3),
        STRUCT('23. nota >= 40',                     'novo',   cum_n3,                  cum_n4),
        STRUCT('24. régua de consenso >= 50',        'novo',   cum_n4,                  cum_n5),
        STRUCT('25. [variante D1] sem mov. de linha','novo',   cum_n3,                  cum_n5_sem_mov)
    ]) AS f
)

SELECT
    escopo,
    regime,
    porta,
    mercado,
    COUNTIF(entrou)                                              AS n_entrada,
    COUNTIF(entrou AND NOT passou)                               AS removidas_marginal,
    COUNTIF(passou)                                              AS n_saida,
    ROUND(SAFE_DIVIDE(COUNTIF(entrou AND NOT passou), NULLIF(COUNTIF(entrou), 0)) * 100, 1) AS pct_removido
{# Cada linha conta duas vezes: no seu mercado e no total. Evita ROLLUP, que no BigQuery
   não convive com outros elementos de agrupamento. #}
FROM funil, UNNEST([market, 'ZZ. TODOS']) AS mercado
GROUP BY escopo, regime, porta, mercado
ORDER BY escopo, regime, porta, mercado
