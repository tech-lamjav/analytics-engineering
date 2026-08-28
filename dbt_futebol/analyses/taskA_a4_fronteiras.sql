{#
    A4 — AS DUAS FRONTEIRAS DE FAIXA, NA ESCALA PÓS-A6 (issue #107)

    A subtask foi ENCURTADA pela decisão do PM de 20/08: o corte de publicação por nota sai
    do back, o board passa a mapear TODAS as faixas e a seleção vira filtro no front. Sobram
    as duas fronteiras de `Alta` / `Média` / `Baixa`.

    **Nada em produção muda nesta entrega.** Quem põe os números em vigor é a virada (#109).

    Rodar com:
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_a4_fronteiras
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/taskA_a4_fronteiras.sql

    ⚠️ RODAR A `taskA_a4_reconciliacao.sql` ANTES, e só seguir se ela vier verde. Ela prova
    que o caminho universo→recomputação→nota desta análise é o mesmo que produziu o seed do
    denominador. Sem isso, a curva abaixo tem a forma de sempre e a escala errada.

    ──────────────────────────────────────────────────────────────────────────────────────
    O UNIVERSO

    Do `fact_value_funnel` (ADR 0011), que é append-only: é ele que torna o recorte
    REPRODUZÍVEL, e a reprodutibilidade é o ponto — a mesma query de backtest, três dias
    depois e sem mudar um byte, moveu a faixa 20–40 de −3,6% para +9,7%. O recorte congelado
    são os dois tetos declarados abaixo, no padrão da `taskA_linha_de_base_funil.sql` (#106).

      · `janela_e_corrente`         uma janela por candidato. O funil guarda até quatro
                                    (daily, t24h, t1h, t15m) e a nota de contexto é a MESMA
                                    nas quatro desde a #103 — contar as quatro faria o jogo
                                    precificado cedo pesar 4×.
      · `gravado_em < {{ var('a4_teto_gravado_em', '2026-08-28 21:00:00') }}`
                                    o teto desta rodada.
      · jogo LIQUIDADO              `fact_fixtures` com placar e status encerrado
                                    (`futebol_jogo_encerrado`), kickoff < o mesmo teto.
      · `lado IS NOT NULL`          a "12" da Dupla Chance sai (não é saída catalogada).

    A NOTA vem RECOMPUTADA dos cinco modelos de premissa, não lida do registro congelado —
    é a rota da A6 (#105) e da `taskA_a40_transporte.sql`, e a razão é a mesma: qualquer
    janela do funil anterior ao deploy da A1 mistura DUAS ESCALAS DO GOLS (tetos 56/52 antes,
    50/46 depois), e numa linha congelada não dá para saber se as duas premissas de movimento
    acenderam. O DENOMINADOR, ao contrário, vem do SEED e nunca é recalculado (ADR 0005).

    O PREÇO (`best_odd`) vem do FUNIL, congelado: é o preço que o Motor viu, não o que o
    de-vig diria hoje.

    ──────────────────────────────────────────────────────────────────────────────────────
    A POPULAÇÃO SOBRE A QUAL AS FRONTEIRAS SÃO DECIDIDAS: o board PÓS-VIRADA

    A faixa é o que o front filtra, então a restrição de forma tem de incidir sobre o que o
    board vai de fato publicar depois da #109 — não sobre o funil inteiro nem sobre o board
    de hoje. O gate pós-virada é recomposto aqui a partir dos insumos CONGELADOS do funil,
    e não lido das colunas de porta, por um motivo: `porta_liquidez_estrita`, `porta_outlier`
    e `porta_faixa_odd` chegaram na #104 por `append_new_columns` e são NULL para sempre nas
    linhas de jogo já apitado — que são exatamente as linhas liquidadas de que esta medição
    precisa. Recompor dos insumos é a única leitura que cobre a série inteira.

      ENTRA (#109):  saída catalogada · conjunto completo · valor estimável · linha meia
                     (AH/Gols) · odd mínima da DC · n_casas >= 4 · sem outlier de odd ·
                     best_odd na faixa do mercado
      SAI   (#109):  `edge > 0`, o piso de edge de consenso e a régua de nota (>= 40)

    ⚠️ Os DOIS LADOS SEM LADO APOSTADO — o `Draw` do 1X2 e o `Pick` do Handicap — ficam FORA
    das restrições de forma e são reportados à parte. Eles têm p95 = 0 e nota 0 POR
    CONSTRUÇÃO (nenhuma premissa se aplica); contá-los dentro faria um terço do 1X2 aparecer
    como `Baixa` e a restrição leria severidade de régua onde há ausência de lado — a
    confusão que a coluna `sem_lado_apostado` existe para impedir (ADR 0005/0006).

    ──────────────────────────────────────────────────────────────────────────────────────
    REGRA DE DECISÃO, FIXADA ANTES DE OLHAR
    ──────────────────────────────────────────────────────────────────────────────────────

    A grade de pares candidatos (B = fronteira Baixa/Média, A = fronteira Média/Alta), em
    INTEIROS sobre a escala normalizada 0–100:

        (20,50) (25,55) (25,60) (30,60) (33,67) (35,65) (40,70) (50,75)

    INCLUSIVIDADE, declarada porque este repositório já teve bug de knife-edge de float:
        Baixa  =  score_normalizado <  B
        Média  =  B <= score_normalizado <  A
        Alta   =  score_normalizado >= A
    O valor da fronteira pertence à faixa DE CIMA, nas duas.

    RESTRIÇÕES (duras, sobre a população pós-virada, excluídos Draw e Pick):
        C1  cada uma das três faixas fica com >= 10% das linhas
        C2  nenhuma faixa fica com > 65% das linhas
        C3  em cada um dos NOVE pares (mercado, lado) com p95 > 0, nenhuma faixa fica vazia

    OBJETIVO, entre os pares que satisfazem C1–C3:
        maximizar  ROI(Alta) − ROI(Baixa)

    DESEMPATE, determinístico:
        1º  o par mais redondo — menor (B mod 5) + (A mod 5)
        2º  menor B

    OS TRÊS RAMOS DE SAÍDA:
      · nenhum par da grade satisfaz C1–C3
            -> NENHUMA fronteira é proposta. A questão vai ao PM, como o aceite manda.
      · o objetivo não discrimina — ROI(Alta) − ROI(Baixa) fica dentro de 1 EP agrupado por
        fixture em TODOS os pares que passam
            -> cai para o par de melhor EQUILÍBRIO (o que minimiza a maior faixa), e o
               achado "a nota não separa ROI nesta janela" é reportado como resultado, não
               escondido como ruído.
      · ROI não monotônico entre as três faixas
            -> é REPORTADO, e não corrigido. Desde a decisão do PM de 20/08 a nota INFORMA e
               não barra: faixa é rótulo, não porta, e não precisa de ROI monotônico para
               existir. Ajustar a grade para "consertar" a monotonia seria escolher depois de
               olhar, que é o que esta seção existe para impedir.

    ⚠️ NENHUM CORTE DE PUBLICAÇÃO É PROPOSTO por esta análise, em ramo nenhum. Se a medição
    sugerir um, ele vai ao PM como pergunta (aceite da #107).

    ──────────────────────────────────────────────────────────────────────────────────────
    O QUE A SAÍDA TRAZ

      bloco = '1. GRADE'      um par por linha: as três faixas, share, ROI, EP e o veredito
                              das restrições. É onde a regra acima é aplicada.
      bloco = '2. CURVA'      a curva de ROI por faixa do par ESCOLHIDO, com EP agrupado por
                              fixture — o que o aceite pede como medição.
      bloco = '3. LADOS'      a distribuição de nota por (mercado, lado): o aceite manda que
                              ela entre na decisão, porque a nota é ABSOLUTA e os mercados
                              publicam em taxas diferentes por desenho (ADR 0005).
      bloco = '4. SEM LADO'   Draw e Pick, à parte, pelo motivo do ⚠️ acima.
#}

{%- set grade = [(20,50), (25,55), (25,60), (30,60), (33,67), (35,65), (40,70), (50,75)] -%}
{%- set teto = var('a4_teto_gravado_em', '2026-08-28 21:00:00') -%}

WITH universo AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.line_value,
        f.kickoff_utc,
        f.best_odd,
        f.n_casas,
        f.pen_odd_outlier,
        f.prob_justa_fechamento,
        f.porta_saida_catalogada,
        f.porta_conjunto_completo,
        {{ futebol_lado('f.market', 'f.outcome', 'f.line_value') }} AS lado
    FROM {{ ref('fact_value_funnel') }} f
    WHERE f.janela_e_corrente
      AND f.gravado_em < TIMESTAMP '{{ teto }}'
      AND f.kickoff_utc < TIMESTAMP '{{ teto }}'
),

{#- A liquidação. O funil não carrega placar nem status de propósito (ADR 0011, D10: status
    muda depois do apito e uma coluna congelada mentiria), então o resultado vem de
    `fact_fixtures`.

    ⚠️ `status_short = 'FT'` E NÃO o `futebol_jogo_encerrado()`, que também aceita `AET` e
    `PEN`. É o predicado do `task01_base`, e a diferença NÃO é estilo: o
    `task01_liquidacao()` liquida mercado de 90 MINUTOS (1X2, Gols, Handicap, BTTS, DC), e
    `goals_home`/`goals_away` de um jogo decidido na prorrogação carregam o placar DEPOIS
    dela. Liquidar um Over 2.5 de mata-mata pelo placar com prorrogação dá vitória a uma
    aposta que perdeu — erro de liquidação, não de escopo. O `futebol_jogo_encerrado()`
    existe para outra pergunta ("o jogo acabou?", que é a do expurgo), e a #71 já separou as
    duas noções no histórico de time. Fica FT, como no artefato que produziu a [0.1]. -#}
jogos AS (
    SELECT fixture_id, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND goals_away IS NOT NULL
),

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

{#- O `market_id` de volta, para a liquidação: o macro `task01_liquidacao` chaveia por id e o
    funil carrega o slug. O mapa vem do `futebol_mercados_pontuados()`, nunca digitado à mão
    (é a razão de aquele macro existir). -#}
com_nota AS (
    SELECT
        r.*,
        CASE r.market
            {%- for mid, slug in futebol_mercados_pontuados().items() %}
            WHEN '{{ slug }}' THEN {{ mid }}
            {%- endfor %}
        END AS market_id,
        -- o `task01_liquidacao()` chaveia por `outcome_side`; o funil chama a mesma coisa
        -- de `outcome`. Renomear aqui, e não reescrever o macro, mantém a liquidação
        -- byte a byte a mesma que produziu os números publicados da [0.1].
        r.outcome AS outcome_side,
        {{ futebol_nota_contexto() }} AS nota_contexto
    FROM recomputado r
    WHERE r.lado IS NOT NULL
),

normalizado AS (
    SELECT
        c.*,
        s.p95,
        {{ futebol_score_normalizado() }} AS score_normalizado
    FROM com_nota c
    -- LEFT: lado ausente do seed vira denominador NULL e o macro o resolve para zero
    -- visível, nunca NULL silencioso. Quem cobra ausência é a guarda de cobertura.
    LEFT JOIN {{ ref('futebol_p95_nota_contexto') }} s
           ON s.market = c.market AND s.lado = c.lado
),

{#- O gate PÓS-VIRADA, recomposto dos insumos congelados — ver a seção do cabeçalho. -#}
publicavel AS (
    SELECT
        n.*,
        j.goals_home,
        j.goals_away,
        {{ task01_liquidacao('n.', 'j.') }} AS ganhou
    FROM normalizado n
    JOIN jogos j ON j.fixture_id = n.fixture_id
    WHERE COALESCE(n.porta_saida_catalogada, FALSE)
      AND COALESCE(n.porta_conjunto_completo, FALSE)
      AND n.prob_justa_fechamento IS NOT NULL
      AND COALESCE(n.n_casas >= {{ var('liquidez_min_casas', 4) }}, FALSE)
      AND NOT COALESCE(n.pen_odd_outlier, TRUE)
      AND n.best_odd IS NOT NULL
      AND CASE
              WHEN n.market = '{{ futebol_mercados_pontuados()[12] }}'
                  THEN n.best_odd BETWEEN {{ var('faixa_odd_dc_min', 1.25) }}
                                      AND {{ var('faixa_odd_dc_max', 2.00) }}
              ELSE     n.best_odd BETWEEN {{ var('faixa_odd_min', 1.50) }}
                                      AND {{ var('faixa_odd_max', 4.00) }}
          END
      -- linha meia só onde a linha existe (AH e Gols); 1X2/BTTS/DC não têm linha.
      AND (n.line_value IS NULL OR {{ futebol_e_linha_meia('n.line_value') }})
),

com_lucro AS (
    SELECT
        *,
        IF(ganhou, best_odd, 0) - 1 AS lucro,
        -- os dois lados sem lado apostado saem das restrições e vão para o bloco 4.
        (lado IN ('Draw', 'Pick')) AS sem_lado_apostado
    FROM publicavel
),

{#- ======================================================================================
    BLOCO 1 — A GRADE. Um par por linha × três faixas.
    ====================================================================================== -#}
grade AS (
    {%- for par in grade %}
    SELECT
        '{{ par[0] }}/{{ par[1] }}' AS par,
        {{ par[0] }} AS b, {{ par[1] }} AS a,
        fixture_id, market, lado, lucro,
        CASE WHEN score_normalizado >= {{ par[1] }} THEN 'Alta'
             WHEN score_normalizado >= {{ par[0] }} THEN 'Media'
             ELSE                                        'Baixa' END AS faixa
    FROM com_lucro WHERE NOT sem_lado_apostado
    {%- if not loop.last %}
    UNION ALL
    {%- endif %}
    {%- endfor %}
),

grade_media AS (
    SELECT g.*, AVG(lucro) OVER (PARTITION BY par, faixa) AS media_faixa
    FROM grade g
),
grade_por_fixture AS (
    SELECT par, faixa, fixture_id, SUM(lucro - media_faixa) AS resid_jogo
    FROM grade_media GROUP BY 1, 2, 3
),
grade_erro AS (
    SELECT par, faixa, SUM(POW(resid_jogo, 2)) AS soma_quad, COUNT(*) AS n_jogos
    FROM grade_por_fixture GROUP BY 1, 2
),
grade_faixa AS (
    SELECT
        g.par, ANY_VALUE(g.b) AS b, ANY_VALUE(g.a) AS a, g.faixa,
        COUNT(*)                                                   AS n_apostas,
        ANY_VALUE(e.n_jogos)                                       AS n_jogos,
        ROUND(AVG(g.lucro) * 100, 1)                               AS roi,
        ROUND(SAFE_DIVIDE(SQRT(ANY_VALUE(e.soma_quad)), COUNT(*)) * 100, 1) AS ep_cluster,
        ROUND(COUNT(*) * 100.0
              / SUM(COUNT(*)) OVER (PARTITION BY g.par), 1)        AS share_pct
    FROM grade_media g
    JOIN grade_erro e USING (par, faixa)
    GROUP BY g.par, g.faixa
),

{#- C3: nenhuma faixa vazia em nenhum dos nove pares (mercado, lado) com p95 > 0. -#}
grade_c3 AS (
    SELECT par,
           MIN(n_faixas_no_lado) = 3 AS c3_ok
    FROM (
        SELECT par, market, lado, COUNT(DISTINCT faixa) AS n_faixas_no_lado
        FROM grade GROUP BY 1, 2, 3
    )
    GROUP BY par
),

grade_veredito AS (
    SELECT
        f.par,
        ANY_VALUE(f.b) AS b, ANY_VALUE(f.a) AS a,
        MIN(f.share_pct)                          AS menor_share,
        MAX(f.share_pct)                          AS maior_share,
        MIN(f.share_pct) >= 10                    AS c1_ok,
        MAX(f.share_pct) <= 65                    AS c2_ok,
        ANY_VALUE(c3.c3_ok)                       AS c3_ok,
        MAX(IF(f.faixa = 'Alta',  f.roi, NULL))
          - MAX(IF(f.faixa = 'Baixa', f.roi, NULL)) AS gap_roi,
        MAX(IF(f.faixa = 'Alta',  f.ep_cluster, NULL)) AS ep_alta,
        MAX(IF(f.faixa = 'Baixa', f.ep_cluster, NULL)) AS ep_baixa
    FROM grade_faixa f
    JOIN grade_c3 c3 USING (par)
    GROUP BY f.par
),

bloco1 AS (
    SELECT
        '1. GRADE' AS bloco,
        v.par AS chave, f.faixa AS sub,
        f.n_apostas, f.n_jogos, f.share_pct, f.roi, f.ep_cluster,
        v.gap_roi,
        CASE WHEN NOT v.c1_ok THEN 'reprova C1 (faixa < 10%)'
             WHEN NOT v.c2_ok THEN 'reprova C2 (faixa > 65%)'
             WHEN NOT v.c3_ok THEN 'reprova C3 (lado com faixa vazia)'
             ELSE                  'passa C1-C3' END AS veredito
    FROM grade_veredito v
    JOIN grade_faixa f USING (par)
),

{#- ======================================================================================
    A ESCOLHA — a regra do cabeçalho aplicada em SQL, e não a olho.

    O ramo E1 ("o objetivo não discrimina") é avaliado ANTES do objetivo, porque é ele que
    decide QUAL objetivo vale. `discrimina` é o gap maior que 1 erro-padrão da DIFERENÇA,
    com o EP da diferença tomado como a raiz da soma dos quadrados dos dois EP de faixa.

    ⚠️ Essa soma IGNORA a covariância: um mesmo fixture pode ter linha na Alta e na Baixa,
    então os dois clusters não são independentes e o EP da diferença é aproximado. A
    aproximação é conservadora para o lado que interessa aqui — ela não INVENTA
    discriminação — e a leitura alternativa (comparar o gap contra o maior dos dois EP de
    faixa, sem somar) devolve o MESMO veredito em todos os oito pares. Está medido, não
    suposto: nenhuma das duas leituras muda o ramo.
    ====================================================================================== -#}
grade_discrimina AS (
    SELECT
        *,
        SQRT(POW(ep_alta, 2) + POW(ep_baixa, 2)) AS ep_gap,
        ABS(gap_roi) > SQRT(POW(ep_alta, 2) + POW(ep_baixa, 2)) AS discrimina
    FROM grade_veredito
    WHERE c1_ok AND c2_ok AND c3_ok
),

ramo AS (
    SELECT
        COUNT(*)                         AS n_pares_validos,
        COUNTIF(discrimina)              AS n_discriminam,
        -- E2: nenhum par passa nas restrições -> nada é proposto.
        -- E1: nenhum par discrimina        -> cai para o melhor equilíbrio.
        CASE WHEN COUNT(*) = 0        THEN 'E2 - nenhum par satisfaz C1-C3: NADA e proposto, a questao vai ao PM'
             WHEN COUNTIF(discrimina) = 0 THEN 'E1 - o objetivo nao discrimina: escolha por EQUILIBRIO'
             ELSE                          'PRINCIPAL - maior gap de ROI entre Alta e Baixa'
        END AS ramo_aplicado
    FROM grade_discrimina
),

escolhido AS (
    SELECT d.par, d.b, d.a
    FROM grade_discrimina d
    CROSS JOIN ramo r
    ORDER BY
        -- no ramo principal manda o gap; no E1 ele é ignorado e manda o equilíbrio
        -- (menor faixa máxima). O desempate é o mesmo nos dois: par mais redondo, menor B.
        CASE WHEN r.n_discriminam > 0 THEN d.gap_roi      ELSE NULL END DESC,
        CASE WHEN r.n_discriminam = 0 THEN d.maior_share  ELSE NULL END ASC,
        (MOD(d.b, 5) + MOD(d.a, 5)) ASC,
        d.b ASC
    LIMIT 1
),

bloco0 AS (
    SELECT
        '0. RAMO DA REGRA' AS bloco,
        r.ramo_aplicado AS chave,
        (SELECT par FROM escolhido) AS sub,
        r.n_pares_validos AS n_apostas,
        r.n_discriminam   AS n_jogos,
        CAST(NULL AS FLOAT64) AS share_pct,
        CAST(NULL AS FLOAT64) AS roi,
        CAST(NULL AS FLOAT64) AS ep_cluster,
        CAST(NULL AS FLOAT64) AS gap_roi,
        'n_apostas = pares que passam C1-C3; n_jogos = quantos discriminam' AS veredito
    FROM ramo r
),

bloco2 AS (
    SELECT
        '2. CURVA (par escolhido)' AS bloco,
        f.par AS chave, f.faixa AS sub,
        f.n_apostas, f.n_jogos, f.share_pct, f.roi, f.ep_cluster,
        CAST(NULL AS FLOAT64) AS gap_roi,
        CAST(NULL AS STRING)  AS veredito
    FROM grade_faixa f
    JOIN escolhido e USING (par)
),

{#- BLOCO 3 — a distribuição por (mercado, lado), que o aceite manda entrar na decisão. -#}
bloco3 AS (
    SELECT
        '3. LADOS' AS bloco,
        c.market || '/' || c.lado AS chave,
        CAST(NULL AS STRING) AS sub,
        COUNT(*)                                    AS n_apostas,
        COUNT(DISTINCT c.fixture_id)                AS n_jogos,
        CAST(NULL AS FLOAT64)                       AS share_pct,
        ROUND(AVG(c.lucro) * 100, 1)                AS roi,
        CAST(NULL AS FLOAT64)                       AS ep_cluster,
        CAST(NULL AS FLOAT64)                       AS gap_roi,
        'nota media ' || CAST(ROUND(AVG(c.score_normalizado), 1) AS STRING)
          || ' | p10 ' || CAST(APPROX_QUANTILES(c.score_normalizado, 10)[OFFSET(1)] AS STRING)
          || ' | mediana ' || CAST(APPROX_QUANTILES(c.score_normalizado, 10)[OFFSET(5)] AS STRING)
          || ' | p90 ' || CAST(APPROX_QUANTILES(c.score_normalizado, 10)[OFFSET(9)] AS STRING)
          AS veredito
    FROM com_lucro c
    WHERE NOT c.sem_lado_apostado
    GROUP BY 1, 2, 3
),

bloco4 AS (
    SELECT
        '4. SEM LADO APOSTADO (fora das restricoes)' AS bloco,
        c.market || '/' || c.lado AS chave,
        CAST(NULL AS STRING) AS sub,
        COUNT(*)                     AS n_apostas,
        COUNT(DISTINCT c.fixture_id) AS n_jogos,
        CAST(NULL AS FLOAT64)        AS share_pct,
        ROUND(AVG(c.lucro) * 100, 1) AS roi,
        CAST(NULL AS FLOAT64)        AS ep_cluster,
        CAST(NULL AS FLOAT64)        AS gap_roi,
        'nota sempre 0 por construcao' AS veredito
    FROM com_lucro c
    WHERE c.sem_lado_apostado
    GROUP BY 1, 2, 3
)

SELECT * FROM bloco0
UNION ALL SELECT * FROM bloco1
UNION ALL SELECT * FROM bloco2
UNION ALL SELECT * FROM bloco3
UNION ALL SELECT * FROM bloco4
ORDER BY bloco, chave, sub
