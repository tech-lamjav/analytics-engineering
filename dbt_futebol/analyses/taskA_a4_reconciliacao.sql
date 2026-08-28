{#
    A4 — RECONCILIAÇÃO POR RESPOSTA CONHECIDA: a máquina desta medição é a da A6?

    Esta análise NÃO produz número da entrega. Ela existe para provar, antes de qualquer
    leitura de ROI, que o caminho universo→recomputação→nota de contexto usado na
    `taskA_a4_fronteiras.sql` é o MESMO que produziu o seed `futebol_p95_nota_contexto`
    (#105, PR #125). Se ele não for, as fronteiras saem medidas numa escala que não é a
    que está em produção, e o defeito seria invisível: a curva de ROI teria a forma de
    sempre e os números estariam errados por um fator que ninguém veria.

    É o mesmo padrão da `taskf_reconciliacao_01.sql` e da `task01_reconciliacao.sql` —
    reconciliação por resposta conhecida. A resposta conhecida aqui são os onze p95 do seed.

    Rodar com:
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_a4_reconciliacao
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/taskA_a4_reconciliacao.sql

    ──────────────────────────────────────────────────────────────────────────────────────
    O CRITÉRIO DE ACEITE, fixado antes de rodar

      · os DOIS lados estruturalmente zerados (1X2/Draw e Handicap/Pick) reproduzem
        EXATAMENTE 0                                                     -> obrigatório
      · os NOVE lados restantes reproduzem o seed dentro de ±2 pontos     -> obrigatório
      · qualquer desvio maior  ->  a máquina NÃO é a da A6. PARAR e diagnosticar antes de
        medir ROI. Não "ajustar a tolerância depois de olhar".

    POR QUE ±2 E NÃO ZERO. A A6 mediu em 2026-08-26 sobre o funil inteiro daquele instante,
    sem teto de `gravado_em`. O funil cresceu desde então: candidato de jogo por vir é
    reescrito a cada ciclo de odds e candidato novo entrou. Reproduzir o recorte de kickoff
    (16/06–31/08, que é o que o seed carimba) reconstrói quase toda a população, mas não
    exatamente a mesma — e a diferença que sobra é crescimento de janela, não divergência de
    máquina. Um p95 é um quantil discreto sobre pontuação inteira: dois dias de rodada o
    movem em ponto, não em dezena. Desvio grande seria outra coisa — outra composição, outro
    eixo de lado, outro universo — e é isso que o critério separa.

    ⚠️ A irreprodutibilidade da #78 é herdada da A6 e não é novidade desta medição: premissa
    recomputada acende em número ligeiramente diferente a cada build com o insumo congelado.
    Ela está DENTRO do ±2, não fora dele.
#}

WITH universo AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.line_value,
        f.kickoff_utc,
        {{ futebol_lado('f.market', 'f.outcome', 'f.line_value') }} AS lado
    FROM {{ ref('fact_value_funnel') }} f
    -- uma janela por candidato, exatamente como a `taskA_a6_p95.sql`.
    WHERE f.janela_e_corrente
      -- o recorte de kickoff que o seed carimba em `janela_inicio` / `janela_fim`.
      AND DATE(f.kickoff_utc) BETWEEN DATE '2026-06-16' AND DATE '2026-08-31'
),

{#- A recomputação. As chaves de junção são as mesmas da `taskA_a6_p95.sql`, que por sua vez
    as copiou do `fact_value_funnel` — reescrevê-las diferente aqui mediria outra coisa. -#}
recomputado AS (
    SELECT u.*, p.pts_premissas, p.penalidades_1x2_pts AS penalidades_especificas_pts
    FROM universo u
    JOIN {{ ref('int_futebol_premissas_1x2') }} p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
    WHERE u.market = '{{ futebol_mercados_pontuados()[1] }}'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_ou_pts
    FROM universo u
    JOIN {{ ref('int_futebol_premissas_ou') }} p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
     AND COALESCE(CAST(p.line_value AS STRING), 'NONE') = u.line_key
    WHERE u.market = '{{ futebol_mercados_pontuados()[5] }}'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_ah_pts
    FROM universo u
    JOIN {{ ref('int_futebol_premissas_ah') }} p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
     AND COALESCE(CAST(p.line_value AS STRING), 'NONE') = u.line_key
    WHERE u.market = '{{ futebol_mercados_pontuados()[4] }}'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_btts_pts
    FROM universo u
    JOIN {{ ref('int_futebol_premissas_btts') }} p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
    WHERE u.market = '{{ futebol_mercados_pontuados()[8] }}'

    UNION ALL
    SELECT u.*, p.pts_premissas, p.penalidades_dc_pts
    FROM universo u
    JOIN {{ ref('int_futebol_premissas_dc') }} p
      ON p.fixture_id = u.fixture_id AND p.outcome = u.outcome
    WHERE u.market = '{{ futebol_mercados_pontuados()[12] }}'
),

com_nota AS (
    SELECT r.*, {{ futebol_nota_contexto() }} AS nota_contexto
    FROM recomputado r
    WHERE r.lado IS NOT NULL
),

medido AS (
    SELECT DISTINCT
        market,
        lado,
        {{ futebol_p95('nota_contexto') }} OVER (PARTITION BY market, lado) AS p95_recomputado,
        COUNT(*) OVER (PARTITION BY market, lado)                           AS n_recomputado
    FROM com_nota
)

SELECT
    m.market,
    m.lado,
    s.p95                          AS p95_seed,
    m.p95_recomputado,
    m.p95_recomputado - s.p95      AS desvio,
    s.n_candidatos                 AS n_seed,
    m.n_recomputado,
    CASE
        WHEN s.p95 = 0 AND m.p95_recomputado = 0             THEN 'OK (zero estrutural)'
        WHEN s.p95 = 0 OR  m.p95_recomputado = 0             THEN 'FALHA (zero de um lado só)'
        WHEN ABS(m.p95_recomputado - s.p95) <= 2             THEN 'OK'
        ELSE                                                      'FALHA (fora de +-2)'
    END AS veredito
FROM medido m
-- FULL OUTER de propósito: lado no seed e ausente da recomputação (ou o inverso) tem de
-- aparecer como linha, nunca sumir no join. Cobertura é metade do que esta análise prova.
FULL OUTER JOIN {{ ref('futebol_p95_nota_contexto') }} s
  ON s.market = m.market AND s.lado = m.lado
ORDER BY m.market, m.lado
