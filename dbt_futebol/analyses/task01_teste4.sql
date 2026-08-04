{#
    Task [0.1] — TESTE 4: o ROI sobe com a nota?  Ticket #8, spec #3.

    A pergunta de produto. Nenhum teste anterior a fez: o Teste 1 mede premissa
    individual contra a linha, o Teste 2 contra o preço, o Teste 3 mede CONTAGEM de
    premissas. Ninguém mediu a NOTA PONDERADA contra o ROI.

    ════════════════════════════════════════════════════════════════════════════════
    QUATRO FONTES DE PESO — e o par que mede a inflação in-sample

    O ADR 0001 exige que nenhuma conclusão de produto saia do corte in-sample. O
    controle previsto lá (pesos do Teste 1) revelou-se fraco no ticket #6: os dois
    testes medem construtos quase ortogonais, então curva plana sob pesos do Teste 1
    não prova ajuste — prova apenas que prever a linha não paga.

    O controle real é temporal, e está no par B/C:

      A. t2_full  · pesos do Teste 2 sobre TODA a janela, ROI sobre TODA a janela
                    -> o pedido literal. In-sample.
      B. t2_h1    · pesos da 1a METADE, ROI sobre a 1a METADE
                    -> in-sample, par de controle
      C. t2_h1    · pesos da 1a METADE, ROI sobre a 2a METADE
                    -> OUT-OF-SAMPLE de verdade

    B e C usam OS MESMOS PESOS e diferem só no conjunto avaliado. A distância entre
    eles é a inflação in-sample, medida em vez de suposta.

      D. t1       · pesos do Teste 1 (universo de 6.042 jogos), ROI sobre toda a janela
                    -> mantido pelo ADR; responde "premissa que prevê bem paga?"

    A permutação (curva nula) fica em `task01_teste4_permutacao.sql`.
    ════════════════════════════════════════════════════════════════════════════════
    PESOS COM PISO DE 5 JOGOS, sempre. No ticket #5 o piso INVERTEU os três maiores
    sinais: `clean_sheets_altos` +17,1 -> −1,7, `superioridade_xg` +5,2 -> −8,9,
    `tende_golear` +3,9 -> −18,5. Peso sem piso faria a nota herdar exatamente o
    artefato que a Task [0] removeu.

    DUAS COMPOSIÇÕES, lado a lado:

      nota_premissas  Σ dos pesos das premissas acesas.
      score_pos_a1    o mesmo + corroboração − penalidades. É o objeto que iria pro ar
                      depois da A1, que remove apenas o componente de VALOR.

    Ambas normalizadas 0–100 POR MERCADO (pelo total de pontos disponíveis naquele
    mercado), e as faixas são agrupadas DEPOIS da normalização: 5 mercados × 5 faixas
    deixaria dezenas de apostas por célula, nenhuma distinguível de zero.

    INTERVALO: erro-padrão AGRUPADO POR FIXTURE, na forma analítica (cluster-robust)
    em vez de bootstrap. É exato para uma média, custa uma passada em vez de centenas,
    e trata a correlação entre apostas do mesmo jogo — que é o que o bootstrap
    agrupado existiria para tratar.

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_teste4
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_teste4.sql
#}

WITH {{ task01_base() }},

{#- Artefato do de-vig de consenso (prob_justa = 1,0 com um só lado precificado): fora,
    sempre. Ver ticket #7. -#}
validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

{#- Metades TEMPORAIS por jogo, não por linha: apostas do mesmo jogo têm de cair juntas,
    senão o "out-of-sample" vaza pelo próprio fixture. -#}
metades AS (
    SELECT
        fixture_id,
        NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM validas)
),

apostas_m AS (
    SELECT v.*, m.metade
    FROM validas AS v
    JOIN metades AS m USING (fixture_id)
),

{#- Linhas do benchmark PREFERIDO de cada mercado — o mesmo critério do Teste 2. Peso
    medido contra consenso não é comparável em grau com peso medido contra linha sharp. -#}
para_peso AS (
    SELECT a.*, pl.premissa, pl.acesa
    FROM apostas_m AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    WHERE a.benchmark = CASE a.market_id
                            WHEN 12 THEN 'derivada'
                            WHEN 8  THEN 'consenso'
                            ELSE         'sharp'
                        END
      AND a.min_jogos >= 5
),

pesos_t2 AS (
    SELECT 'A. t2_full' AS fonte, market_id, premissa,
           GREATEST((AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
                   - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(acesa), COUNTIF(acesa) + 50) AS peso
    FROM para_peso
    GROUP BY market_id, premissa

    UNION ALL
    SELECT 'B. t2_h1', market_id, premissa,
           GREATEST((AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
                   - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(acesa), COUNTIF(acesa) + 50)
    FROM para_peso WHERE metade = 1
    GROUP BY market_id, premissa
),

{#- Peso de controle do Teste 1: universo de TODO jogo encerrado, sem exigir odd. Mesma
    regra de encolhimento e mesmo piso, p/ que as fontes sejam comparáveis. -#}
t1_linhas AS (
    SELECT
        pl.market_id, pl.fixture_id, pl.outcome_side, pl.line_value, pl.premissa, pl.acesa,
        COALESCE(pit.min_jogos, 0)          AS min_jogos,
        {{ task01_liquidacao('pl.', 'j.') }} AS ganhou
    FROM prem_long AS pl
    JOIN jogos_encerrados AS j ON j.fixture_id = pl.fixture_id
    LEFT JOIN pit ON pit.fixture_id = pl.fixture_id
    WHERE {{ task01_meia_linha('pl.') }}
),
t1_base AS (
    SELECT market_id, outcome_side, line_value, AVG(CAST(ganhou AS INT64)) AS taxa_base
    FROM (SELECT DISTINCT market_id, fixture_id, outcome_side, line_value, ganhou FROM t1_linhas)
    GROUP BY 1, 2, 3
),
pesos_t1 AS (
    SELECT 'D. t1_controle' AS fonte, l.market_id, l.premissa,
           GREATEST((AVG(IF(l.acesa, CAST(l.ganhou AS INT64), NULL))
                   - AVG(IF(l.acesa, b.taxa_base, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(l.acesa), COUNTIF(l.acesa) + 50) AS peso
    FROM t1_linhas AS l
    JOIN t1_base AS b
      ON  b.market_id                  = l.market_id
      AND b.outcome_side               = l.outcome_side
      AND COALESCE(b.line_value, -999) = COALESCE(l.line_value, -999)
    WHERE l.min_jogos >= 5
    GROUP BY l.market_id, l.premissa
),

pesos AS (
    SELECT * FROM pesos_t2 UNION ALL SELECT * FROM pesos_t1
),
teto AS (
    SELECT fonte, market_id, SUM(peso) AS pts_max
    FROM pesos GROUP BY fonte, market_id
),

{#- Nota por (aposta, fonte de peso). -#}
notas AS (
    SELECT
        a.fixture_id, a.market_id, a.metade, a.ganhou, a.best_odd,
        a.pts_corroboracao, a.penalidades_globais_pts, a.penalidades_especificas_pts,
        p.fonte,
        SUM(IF(pl.acesa, p.peso, 0)) AS nota_pts,
        ANY_VALUE(t.pts_max)         AS pts_max
    FROM apostas_m AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    JOIN pesos AS p
      ON p.market_id = pl.market_id AND p.premissa = pl.premissa
    JOIN teto AS t
      ON t.fonte = p.fonte AND t.market_id = a.market_id
    GROUP BY a.fixture_id, a.market_id, a.metade, a.ganhou, a.best_odd,
             a.pts_corroboracao, a.penalidades_globais_pts, a.penalidades_especificas_pts,
             a.outcome_side, a.line_value, p.fonte
),

{#- Duas composições, e o universo de avaliação de cada fonte. O par B/C usa os MESMOS
    pesos: B avalia na metade em que eles foram ajustados, C na outra. -#}
avaliado AS (
    SELECT
        CASE WHEN fonte = 'B. t2_h1' AND metade = 2 THEN 'C. t2_h1 -> 2a metade (OUT-OF-SAMPLE)'
             WHEN fonte = 'B. t2_h1'                THEN 'B. t2_h1 -> 1a metade (in-sample)'
             ELSE fonte END                                          AS avaliacao,
        composicao.nome                                              AS composicao,
        fixture_id,
        LEAST(GREATEST(SAFE_DIVIDE(composicao.pts, composicao.teto) * 100, 0), 100) AS nota_pct,
        IF(ganhou, best_odd, 0) - 1                                  AS lucro
    FROM notas
    CROSS JOIN UNNEST([
        STRUCT('1. nota_premissas' AS nome, nota_pts AS pts, pts_max AS teto),
        STRUCT('2. score_pos_a1'   AS nome,
               nota_pts + pts_corroboracao
                        - penalidades_globais_pts - penalidades_especificas_pts AS pts,
               pts_max + 15 AS teto)
    ]) AS composicao
    WHERE pts_max > 0
),

com_faixa AS (
    SELECT *,
           CASE WHEN nota_pct >= 80 THEN 'e. 80-100'
                WHEN nota_pct >= 60 THEN 'd. 60-80'
                WHEN nota_pct >= 40 THEN 'c. 40-60'
                WHEN nota_pct >= 20 THEN 'b. 20-40'
                ELSE                     'a. 00-20' END AS faixa,
           AVG(lucro) OVER (PARTITION BY avaliacao, composicao,
                            CASE WHEN nota_pct >= 80 THEN 5 WHEN nota_pct >= 60 THEN 4
                                 WHEN nota_pct >= 40 THEN 3 WHEN nota_pct >= 20 THEN 2
                                 ELSE 1 END)            AS media_faixa
    FROM avaliado
),

{#- Erro-padrão agrupado por fixture: soma dos resíduos DENTRO do jogo, ao quadrado,
    somada entre jogos, sobre n². É a variância cluster-robusta da média. -#}
por_fixture AS (
    SELECT avaliacao, composicao, faixa, fixture_id,
           SUM(lucro - media_faixa) AS resid_jogo
    FROM com_faixa
    GROUP BY 1, 2, 3, 4
),
erro AS (
    SELECT avaliacao, composicao, faixa,
           SUM(POW(resid_jogo, 2)) AS soma_quad,
           COUNT(*)                AS n_jogos
    FROM por_fixture GROUP BY 1, 2, 3
),

faixas AS (
    SELECT
        c.avaliacao, c.composicao, c.faixa,
        COUNT(*)                                   AS n_apostas,
        e.n_jogos,
        ROUND(AVG(c.nota_pct), 1)                  AS nota_media,
        ROUND(AVG(c.lucro) * 100, 1)               AS roi,
        ROUND(SAFE_DIVIDE(SQRT(e.soma_quad), COUNT(*)) * 100, 1) AS ep_cluster,
        CAST(NULL AS FLOAT64)                      AS inclinacao
    FROM com_faixa AS c
    JOIN erro AS e USING (avaliacao, composicao, faixa)
    GROUP BY c.avaliacao, c.composicao, c.faixa, e.soma_quad, e.n_jogos
),

{#- A pergunta "sobe?" sem binning: inclinação do lucro contra a nota (pp de ROI por
    ponto de nota) e a correlação. Usa todas as apostas, sem perder poder p/ faixa. -#}
continuo AS (
    SELECT
        avaliacao, composicao, 'z. CONTINUO (todas)' AS faixa,
        COUNT(*)                                       AS n_apostas,
        COUNT(DISTINCT fixture_id)                     AS n_jogos,
        ROUND(AVG(nota_pct), 1)                        AS nota_media,
        ROUND(AVG(lucro) * 100, 1)                     AS roi,
        CAST(NULL AS FLOAT64)                          AS ep_cluster,
        -- pp de ROI por ponto de nota. Positivo = o ROI sobe com a nota.
        ROUND(COVAR_SAMP(lucro, nota_pct)
              / NULLIF(VAR_SAMP(nota_pct), 0) * 100, 3) AS inclinacao
    FROM com_faixa
    GROUP BY avaliacao, composicao
)

SELECT * FROM faixas
UNION ALL SELECT * FROM continuo
ORDER BY composicao, avaliacao, faixa
