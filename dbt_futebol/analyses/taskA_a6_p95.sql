{#
    A6 — O DENOMINADOR CONGELADO: o p95 da nota de contexto por (mercado, lado).

    Esta análise MEDE o número que vai ao seed `futebol_p95_nota_contexto`. Ela roda uma vez,
    o resultado é copiado para o CSV à mão, e a partir daí quem manda é o CSV — recalcular o
    denominador em runtime é falha de aceite da issue #105: um denominador que se move faz a
    régua significar coisa diferente a cada dia e mata toda comparação histórica.

    Rodar com:
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_a6_p95
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/taskA_a6_p95.sql

    ──────────────────────────────────────────────────────────────────────────────────────
    O UNIVERSO: candidatos, lidos do funil — nunca o board

    O board é o que já passou nas oito portas. Medir o p95 sobre ele mediria a distribuição
    do que sobreviveu à régua de 40, que é a própria coisa que o denominador existe para
    reescalar: o denominador sairia calibrado para manter em cima quem já estava em cima.
    O funil guarda o universo inteiro, rejeitados inclusive (ADR 0006/0011), e é dele que a
    medição sai.

    ⚠️ UMA JANELA POR CANDIDATO. O funil guarda até QUATRO linhas por candidato (daily,
    t24h, t1h, t15m) e a nota de contexto é a MESMA nas quatro — desde a #103 nenhuma
    premissa lê movimento de odd, então nada nela depende da janela. Contando as quatro, o
    jogo precificado cedo pesaria até 4× no percentil, e o p95 descreveria "quem foi
    precificado por mais tempo" em vez de "quanta evidência acende". `janela_e_corrente`
    fixa uma, e é a regra que a guarda de deriva repete.

    ──────────────────────────────────────────────────────────────────────────────────────
    A ROTA: premissas RECOMPUTADAS, não lidas do registro — e em todos os cinco mercados

    O funil é append-only e congelado no apito (#96, ADR 0011): a linha de jogo já apitado
    não é reescrita por build nenhum. Ele também não guarda `evidencias[]` (ADR 0011). Junte
    isso à #103, que tirou `linha_subindo`/`linha_descendo` do Gols e derrubou os tetos de
    56/52 para 50/46, e o resultado é que qualquer janela do funil que inclua candidato
    anterior ao deploy da A1 mistura DUAS ESCALAS DO GOLS — e não há como separá-las depois,
    porque não dá para saber, numa linha congelada, se as duas premissas de movimento
    acenderam.

    Por isso a nota de contexto aqui é RECOMPUTADA: o universo (quais candidatos existiram,
    e quando) vem do funil, e os pontos vêm dos cinco modelos de premissa como eles estão
    HOJE. É o padrão da `taskA_a40_transporte.sql`, e é o que a issue #105 autoriza
    explicitamente — inclusive a recomputar os cinco mercados em vez de só o Gols, desde que
    dito e não implícito. Está dito: **os onze lados vêm de recomputação**, e o seed carrega
    `origem = 'recomputacao'` nos onze. Os outros quatro mercados não precisariam (a A1 só
    mexeu na escala do Gols), mas uma medição com duas procedências obrigaria toda leitura
    futura a saber qual linha veio de onde.

    ⚠️ LIMITE CONHECIDO, e é o preço de não esperar: premissa recomputada está sujeita à
    irreprodutibilidade da #78 — premissa que acende em número diferente de linhas a cada
    build, com o insumo congelado. É a razão de o funil existir. A alternativa era declarar
    a janela começando no deploy da #103 e esperar semanas de coleta, adiando a A6 e, com
    ela, a #106 e a #107.

    ──────────────────────────────────────────────────────────────────────────────────────
    A QUANTIDADE MEDIDA: a nota de contexto, não `pts_premissas`

    Numerador e denominador têm de ser a mesma coisa. A nota normalizada divide
    `GREATEST(pts_premissas − penalidades_de_contexto, 0)` — que é `futebol_nota_contexto()`,
    a coluna que a #103 pôs no funil — e é o p95 DELA que o seed congela.

    ⚠️ Os números 44 (Gols Over) e 26 (Handicap favorito) da tabela da ADR 0005 são
    ILUSTRAÇÃO PRÉ-A1, medidos noutra escala do Gols e sobre a soma de pesos. Não são o
    esperado desta medição, e divergir deles não é defeito.

    Os três tetos que a tabela de origem errava entram corrigidos, e saem conferidos na
    coluna `teto_catalogo` abaixo: Resultado Fora é 47 (o `pts_mando` do visitante vale 4),
    Empate é 0, e o "Não" do Ambos Marcam é 28 (12+10+6).
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
    -- uma janela por candidato — ver o ⚠️ do cabeçalho.
    WHERE f.janela_e_corrente
),

-- ============================================================================
-- A RECOMPUTAÇÃO. O universo (esquerda) vem do funil; os pontos (direita) vêm dos cinco
-- modelos de premissa como eles estão hoje. As chaves de junção são as MESMAS que o
-- `fact_value_funnel` usa em cada ramo — copiá-las diferente aqui mediria outra coisa.
-- ============================================================================
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
    SELECT
        r.*,
        -- a MESMA composição que o funil grava, do mesmo macro. As duas colunas de que ele
        -- depende chegam acima com o nome que ele espera.
        {{ futebol_nota_contexto() }} AS nota_contexto
    FROM recomputado r
    -- saída fora do catálogo (a "12" da DC) resolve o lado para NULL e sai da medição.
    WHERE r.lado IS NOT NULL
),

medido AS (
    SELECT DISTINCT
        market,
        lado,
        {{ futebol_p95('nota_contexto') }} OVER (PARTITION BY market, lado) AS p95,
        COUNT(*)                OVER (PARTITION BY market, lado) AS n_candidatos,
        COUNTIF(nota_contexto IS NOT NULL)
                                OVER (PARTITION BY market, lado) AS n_avaliados,
        MAX(nota_contexto)      OVER (PARTITION BY market, lado) AS maximo_observado,
        AVG(nota_contexto)      OVER (PARTITION BY market, lado) AS media_observada,
        COUNTIF(nota_contexto = 0)
                                OVER (PARTITION BY market, lado) AS n_em_zero,
        MIN(DATE(kickoff_utc))  OVER (PARTITION BY market, lado) AS janela_inicio,
        MAX(DATE(kickoff_utc))  OVER (PARTITION BY market, lado) AS janela_fim
    FROM com_nota
)

SELECT
    market,
    lado,
    p95,
    -- o teto do catálogo, escrito à mão, para conferir de olho quem SATURA (p95 = teto) e
    -- quem não chega perto. Os três valores que a tabela de origem errava estão aqui
    -- corrigidos: 1X2 Away 47, 1X2 Draw 0, BTTS No 28.
    CASE market || '/' || lado
        WHEN '{{ futebol_mercados_pontuados()[1] }}/Home'     THEN 51
        WHEN '{{ futebol_mercados_pontuados()[1] }}/Away'     THEN 47
        WHEN '{{ futebol_mercados_pontuados()[1] }}/Draw'     THEN 0
        WHEN '{{ futebol_mercados_pontuados()[5] }}/Over'     THEN 50
        WHEN '{{ futebol_mercados_pontuados()[5] }}/Under'    THEN 46
        WHEN '{{ futebol_mercados_pontuados()[4] }}/Favorito' THEN 40
        WHEN '{{ futebol_mercados_pontuados()[4] }}/Azarao'   THEN 30
        WHEN '{{ futebol_mercados_pontuados()[4] }}/Pick'     THEN 0
        WHEN '{{ futebol_mercados_pontuados()[8] }}/Yes'      THEN 34
        WHEN '{{ futebol_mercados_pontuados()[8] }}/No'       THEN 28
        WHEN '{{ futebol_mercados_pontuados()[12] }}/unico'   THEN 34
    END AS teto_catalogo,
    n_candidatos,
    n_avaliados,
    n_em_zero,
    maximo_observado,
    ROUND(media_observada, 2) AS media_observada,
    -- quanto a nota normalizada mudaria a média deste lado — a amplitude que a ADR 0005
    -- diz que cai de 3,8× para 2,1×, e que NÃO some.
    ROUND(SAFE_DIVIDE(media_observada, p95) * 100, 1) AS media_normalizada,
    janela_inicio,
    janela_fim
FROM medido
ORDER BY market, lado
