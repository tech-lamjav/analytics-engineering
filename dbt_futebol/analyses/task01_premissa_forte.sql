{#
    Task [0.1] — A VARIANTE DE PREMISSA FORTE, in-sample contra out-of-sample.
    Ticket #9, spec #3.

    ════════════════════════════════════════════════════════════════════════════════
    POR QUE ESTA ANÁLISE EXISTE SEPARADA

    O `task01_teste4_piso.sql` mostrou que exigir ao menos uma premissa "forte" produz
    o PRIMEIRO ROI positivo de toda a investigação: +10,0% no piso 0, +7,5% no piso 5,
    +8,3% no piso 10, sobre 1.200 a 1.300 apostas.

    Esse número não pode ser reportado como está. "Forte" é definido pelo ganho do
    Teste 2 medido NOS MESMOS DADOS em que o ROI é medido. Selecionar apostas por um
    critério ajustado à amostra e depois avaliar na mesma amostra é exatamente o
    procedimento que produziu os +9,7% que a Task [0] matou — trocado de vazamento
    temporal por vazamento de seleção, mas o mesmo erro.

    Esta análise faz a única pergunta que dá sentido àquele número:

        Se "forte" for decidido SÓ com a 1a metade da janela, o filtro ainda paga
        na 2a metade?

    Se sim, é o achado mais importante da task. Se não, é o artefato se repetindo com
    roupa nova — e é melhor descobrir aqui do que num comentário publicado.
    ════════════════════════════════════════════════════════════════════════════════
    Quatro linhas por piso, e a comparação que importa é a 3a contra a 4a:

      1. todas as apostas, 2a metade                  <- referência
      2. forte definido em TODA a janela, ROI em toda <- in-sample (o numero de cima)
      3. forte definido em TODA a janela, ROI na 2a   <- ainda contaminado (H2 ⊂ tudo)
      4. forte definido só na 1a metade, ROI na 2a    <- OUT-OF-SAMPLE de verdade

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_premissa_forte
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_premissa_forte.sql
#}

{%- set pisos = [0, 5, 10] -%}
{%- set limiar = 5 -%}

WITH {{ task01_base() }},

validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

metades AS (
    SELECT fixture_id, NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM validas)
),

linhas AS (
    SELECT a.*, m.metade, pl.premissa, pl.acesa
    FROM validas AS a
    JOIN metades AS m USING (fixture_id)
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
),

{#- Ganho do Teste 2 por (piso, janela de ajuste). `janela` = 'tudo' ou 'h1'. -#}
ganhos AS (
    {%- set combos = [] -%}
    {%- for piso in pisos -%}
        {%- for jf in [('tudo', 'TRUE'), ('h1', 'metade = 1')] -%}
            {%- set _ = combos.append((piso, jf[0], jf[1])) -%}
        {%- endfor -%}
    {%- endfor -%}
    {%- for piso, janela, filtro in combos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        {{ piso }} AS piso, '{{ janela }}' AS janela, market_id, premissa,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS ganho,
        COUNTIF(acesa)                                      AS n_ajuste
    FROM linhas
    WHERE min_jogos >= {{ piso }}
      AND {{ filtro }}
      AND benchmark = CASE market_id WHEN 12 THEN 'derivada'
                                     WHEN 8  THEN 'consenso'
                                     ELSE         'sharp' END
    GROUP BY market_id, premissa
    {%- endfor %}
),

{#- Uma aposta "tem forte" se alguma premissa acesa nela tem ganho >= limiar, segundo a
    janela de ajuste em questão. -#}
apostas_forte AS (
    SELECT
        l.fixture_id, l.market_id, l.outcome_side, l.line_value, l.metade, l.min_jogos,
        g.piso, g.janela,
        LOGICAL_OR(l.acesa AND g.ganho >= {{ limiar }})       AS tem_forte,
        IF(ANY_VALUE(l.ganhou), ANY_VALUE(l.best_odd), 0) - 1 AS lucro
    FROM linhas AS l
    JOIN ganhos AS g
      ON g.market_id = l.market_id AND g.premissa = l.premissa
    WHERE l.min_jogos >= g.piso
    GROUP BY l.fixture_id, l.market_id, l.outcome_side, l.line_value,
             l.metade, l.min_jogos, g.piso, g.janela
),

cenarios AS (
    SELECT piso, '1. todas as apostas, 2a metade' AS cenario, lucro, fixture_id
    FROM apostas_forte WHERE janela = 'tudo' AND metade = 2

    UNION ALL
    SELECT piso, '2. forte de TODA a janela, ROI em toda (IN-SAMPLE)', lucro, fixture_id
    FROM apostas_forte WHERE janela = 'tudo' AND tem_forte

    UNION ALL
    SELECT piso, '3. forte de TODA a janela, ROI na 2a metade', lucro, fixture_id
    FROM apostas_forte WHERE janela = 'tudo' AND tem_forte AND metade = 2

    UNION ALL
    SELECT piso, '4. forte so da 1a metade, ROI na 2a (OUT-OF-SAMPLE)', lucro, fixture_id
    FROM apostas_forte WHERE janela = 'h1' AND tem_forte AND metade = 2
),

media AS (
    SELECT piso, cenario, AVG(lucro) AS m FROM cenarios GROUP BY piso, cenario
),
resid AS (
    SELECT c.piso, c.cenario, c.fixture_id, SUM(c.lucro - m.m) AS r
    FROM cenarios AS c JOIN media AS m USING (piso, cenario)
    GROUP BY 1, 2, 3
)

SELECT
    CONCAT('piso ', LPAD(CAST(c.piso AS STRING), 2, '0')) AS corte,
    c.cenario,
    COUNT(*)                                              AS n_apostas,
    COUNT(DISTINCT c.fixture_id)                          AS n_jogos,
    ROUND(AVG(c.lucro) * 100, 1)                          AS roi,
    -- erro-padrão agrupado por fixture
    ROUND(SAFE_DIVIDE(SQRT(ANY_VALUE(e.soma_quad)), COUNT(*)) * 100, 1) AS ep_cluster
FROM cenarios AS c
JOIN (SELECT piso, cenario, SUM(POW(r, 2)) AS soma_quad FROM resid GROUP BY 1, 2) AS e
  USING (piso, cenario)
GROUP BY c.piso, c.cenario
ORDER BY corte, cenario
