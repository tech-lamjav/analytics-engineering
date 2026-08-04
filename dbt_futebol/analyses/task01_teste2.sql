{#
    Task [0.1] — TESTE 2 completo nos 5 mercados, base limpa, e derivação do peso
    medido.  Ticket #5, spec #3.

    O Teste 2 mede se a premissa BATE O PREÇO, e é o único dos quatro que pode
    justificar um peso. O Teste 1 mede outra coisa (prever a linha) — foi essa distinção
    que primeiro salvou e depois derrubou o `xg_combinado_alto`.

        diferença = média(acerto | premissa acesa) − média(prob justa | premissa acesa)

    ────────────────────────────────────────────────────────────────────────────────
    BENCHMARK: a tabela sai por (mercado, premissa, BENCHMARK), e não por (mercado,
    premissa).

    A Pinnacle não cobre todos os jogos. Handicap e Gols são MISTOS — cerca de metade
    das linhas tem preço sharp e metade cai no consenso (mediana das casas). A rodada
    anterior mediu só as sharp; juntar as duas metades numa linha só misturaria dois
    benchmarks de graus diferentes dentro do mesmo número.

    O PESO é derivado apenas do MELHOR benchmark disponível de cada mercado:

        1X2, Handicap, Gols   sharp      (de-vig direto da Pinnacle)
        Dupla Chance          derivada   (do de-vig 1X2 da Pinnacle — âncora sharp)
        BTTS                  consenso   (a Pinnacle estruturalmente não precifica)

    As linhas de consenso do Handicap e do Gols vão na saída assim mesmo, marcadas com
    `usado_para_peso = false`. Elas não pesam, mas precisam ser vistas: o ROI delas é
    muito pior que o das sharp (−26,7 contra −6,5 no Handicap), e essa diferença não é
    do benchmark — é de QUAIS jogos a Pinnacle escolhe precificar. Ignorá-las
    esconderia isso.
    ────────────────────────────────────────────────────────────────────────────────
    PESO (ADR 0001):

        peso = max(diferença, 0) × n / (n + k)          k = 50

    Encolhimento por amostra, não ganho cru. O achado central da Task [0] foi que
    amostra curta fabrica sinal: os +9,7% que morreram vinham inteiramente de
    competições de mata-mata com 0,8 a 2,4 jogos disputados. Peso proporcional ao ganho
    bruto daria as maiores notas justamente às premissas que acenderam poucas vezes.
    `peso_k0` (sem encolhimento) vai junto como sensibilidade.

    Ganho negativo vira peso ZERO, não peso negativo: com esta amostra, uma diferença de
    −5 é indistinguível de ruído, e peso negativo fitaria esse ruído.
    ────────────────────────────────────────────────────────────────────────────────
    `jogos_medios` e `pct_amostra_curta` existem para amarrar cada premissa ao artefato
    que matou a medição anterior. Premissa com ganho alto E `pct_amostra_curta` alto é
    exatamente o padrão que produziu os +9,7%.

    Universo: TODOS os jogos liquidados com odd, sem corte congelado — a janela exata
    sai nas duas primeiras colunas.

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_teste2
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_teste2.sql
#}

WITH {{ task01_base() }},

{#- Uma passada, grão (mercado, premissa, benchmark). Só as linhas em que a premissa
    ACENDEU entram nas médias — é essa a definição do Teste 2. -#}
agregado AS (
    SELECT
        a.market_id,
        pl.premissa,
        a.benchmark,
        COUNTIF(pl.acesa)                                        AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL))         AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL))         AS p_real,
        AVG(IF(pl.acesa, a.min_jogos, NULL))                     AS jogos_medios,
        AVG(IF(pl.acesa, IF(a.min_jogos < 5, 1.0, 0.0), NULL))   AS frac_curta
    FROM apostas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    GROUP BY a.market_id, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
),

janela AS (
    SELECT
        MIN(DATE(kickoff_utc)) AS janela_ini,
        MAX(DATE(kickoff_utc)) AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*) AS linhas_no_universo
    FROM apostas
)

SELECT
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    CASE g.market_id
        {%- for mid, m in task01_markets().items() %}
        WHEN {{ mid }} THEN '{{ m.nome }}'
        {%- endfor %}
    END                                                     AS mercado,
    g.premissa,
    g.benchmark,
    -- O melhor benchmark disponível de cada mercado. Só estas linhas geram peso.
    (g.benchmark = CASE g.market_id
                       WHEN 12 THEN 'derivada'
                       WHEN 8  THEN 'consenso'
                       ELSE         'sharp'
                   END)                                     AS usado_para_peso,
    g.n,
    ROUND(g.p_odd  * 100, 1)                                AS a_odd_dava,
    ROUND(g.p_real * 100, 1)                                AS aconteceu,
    ROUND((g.p_real - g.p_odd) * 100, 1)                    AS diferenca,
    ROUND(g.jogos_medios, 1)                                AS jogos_medios,
    ROUND(g.frac_curta * 100, 1)                            AS pct_amostra_curta,
    -- peso = max(diferença, 0) × n/(n+k). k=50 é o encolhimento por amostra; k=0 é a
    -- sensibilidade que mostra o quanto o encolhimento está segurando.
    IF(g.benchmark = CASE g.market_id
                         WHEN 12 THEN 'derivada'
                         WHEN 8  THEN 'consenso'
                         ELSE         'sharp'
                     END,
       ROUND(GREATEST((g.p_real - g.p_odd) * 100, 0) * SAFE_DIVIDE(g.n, g.n + 50), 2),
       NULL)                                                AS peso_k50,
    IF(g.benchmark = CASE g.market_id
                         WHEN 12 THEN 'derivada'
                         WHEN 8  THEN 'consenso'
                         ELSE         'sharp'
                     END,
       ROUND(GREATEST((g.p_real - g.p_odd) * 100, 0), 2),
       NULL)                                                AS peso_k0
FROM agregado AS g
CROSS JOIN janela AS j
ORDER BY mercado, usado_para_peso DESC, diferenca DESC
