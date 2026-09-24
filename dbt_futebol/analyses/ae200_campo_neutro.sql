{#
    A MEDIÇÃO DO CAMPO NEUTRO (AE#200) — a metade de leitura. Compara as duas células que
    analyses/ae200_campo_neutro_celula.sql congelou em `futebol_taskF.ae200_celulas`:
    `ambos` (produção, rótulo da API) × `ambos_neutro_copa` (a regra da Copa). A reprodução
    inteira, com a ordem dos builds, está no cabeçalho daquele arquivo.

    ────────────────────────────────────────────────────────────────────────────────
    AS DUAS PERGUNTAS, NESTA ORDEM (decididas na grilling de 24/09)

      (a) vale shipar? — quanto o acendimento e a faixa mudam nas linhas EXPOSTAS.
      (b) shipar exige remedir a calibração 30/60? — a régua: se MENOS DE 1% das linhas com
          preço do agregado troca de faixa, a calibração fica intocada. Acima, vira pergunta
          ao PM, não decisão nossa.

    ────────────────────────────────────────────────────────────────────────────────
    OS TRÊS RECORTES

      agregado      toda linha de competição rateada, MENOS as de jogo de Copa do Mundo.
                    Competição de insumo (amistosos) fica fora de tudo: não é rateada.
      exposto       o subconjunto do agregado cujo fixture tem pelo menos um dos dois times
                    com campo neutro nos últimos 10 (played_neutro > 0 na célula neutra).
      copa_rateada  as linhas de jogo de Copa. À parte, porque ali o LADO do próprio jogo-alvo
                    também é rótulo do sorteio, e a célula não o corrige (fora de escopo por
                    decisão: produção só volta a ratear Copa em 2030). É a maior amostra
                    exposta, e responde uma pergunta que produção não vai fazer tão cedo.

    Fora de escopo, declarado: campo neutro de CLUBE (os ~1% da ADR 0015 não são enxergados
    pela regra da Copa) e amistosos (entram no mart só a partir de 23/09).

    ────────────────────────────────────────────────────────────────────────────────
    ACENDIMENTO sai de toda linha dos modelos de premissa (não precisa de preço). FAIXA sai
    só das linhas que tiveram preço — as chaves do `fact_value_funnel` de produção — com a
    nota recomposta dos pts de cada célula pelos macros de produção
    (futebol_nota_contexto → futebol_score_normalizado, teto do seed). O lado é recomputado
    por futebol_lado() e não lido do funil: as linhas congeladas antes da #105 têm `lado`
    NULL, e são justamente as da Copa.
    ⚠️ Os cortes da faixa (>=60 Alta, >=30 Média) são uma CÓPIA dos de
    fact_value_opportunities.sql — a faixa não tem macro. Se lá mudar, muda aqui.

    São quatro SELECTs; o `bq query` imprime um por um.
#}
{%- set destino = 'smartbetting-dados.futebol_taskF' -%}
{%- set antes  = 'ambos' -%}
{%- set depois = 'ambos_neutro_copa' -%}

CREATE TEMP TABLE par AS
WITH exposicao AS (
    SELECT fixture_id, MAX(played_neutro) > 0 AS exposto
    FROM `{{ destino }}.ae200_pit`
    WHERE celula = '{{ depois }}'
    GROUP BY fixture_id
),
com_preco AS (
    SELECT DISTINCT fixture_id, market, outcome, CAST(line_value AS FLOAT64) AS line_value
    FROM `smartbetting-dados.futebol.fact_value_funnel`
),
lados AS (
    SELECT
        c.*,
        {{ futebol_lado('c.market', 'c.outcome', 'c.line_value', 'c.is_favorito') }} AS lado
    FROM `{{ destino }}.ae200_celulas` c
),
notas AS (
    SELECT
        l.*,
        s.teto,
        {{ futebol_nota_contexto() }} AS nota_contexto
    FROM lados l
    LEFT JOIN {{ ref('futebol_teto_nota_contexto') }} s
        ON s.market = l.market AND s.lado = l.lado
),
scores AS (
    SELECT *, {{ futebol_score_normalizado() }} AS score_normalizado
    FROM notas
),
celula AS (
    SELECT
        *,
        CASE
            WHEN score_normalizado IS NULL THEN NULL
            WHEN score_normalizado >= 60   THEN 'Alta'
            WHEN score_normalizado >= 30   THEN 'Média'
            ELSE 'Baixa'
        END AS faixa
    FROM scores
)
SELECT
    a.market, a.fixture_id, a.competition, a.outcome, a.line_value,
    CASE
        -- Competição de INSUMO (amistosos) entra no histórico mas nunca é rateada: não tem
        -- linha no funil, e contar o acendimento dela diluiria o exposto com jogo que ninguém
        -- vê. Fica fora dos três recortes.
        WHEN a.competition IN {{ futebol_competicoes_insumo_slugs_sql() }} THEN 'insumo'
        WHEN a.competition = 'copa_mundo'          THEN 'copa_rateada'
        WHEN COALESCE(e.exposto, FALSE)            THEN 'exposto'
        ELSE 'nao_exposto'
    END                                             AS grupo,
    p.fixture_id IS NOT NULL                        AS teve_preco,
    a.premissas                                     AS premissas_antes,
    d.premissas                                     AS premissas_depois,
    a.premissas_sem_dado                            AS sem_dado_antes,
    d.premissas_sem_dado                            AS sem_dado_depois,
    a.score_normalizado                             AS score_antes,
    d.score_normalizado                             AS score_depois,
    a.faixa                                         AS faixa_antes,
    d.faixa                                         AS faixa_depois
FROM celula a
JOIN celula d
    ON  d.celula     = '{{ depois }}'
    AND d.market     = a.market
    AND d.fixture_id = a.fixture_id
    AND d.outcome    = a.outcome
    AND d.line_value IS NOT DISTINCT FROM a.line_value
LEFT JOIN exposicao e
    ON e.fixture_id = a.fixture_id
LEFT JOIN com_preco p
    ON  p.fixture_id = a.fixture_id
    AND p.market     = a.market
    AND p.outcome    = a.outcome
    AND p.line_value IS NOT DISTINCT FROM a.line_value
WHERE a.celula = '{{ antes }}';

-- Os três recortes sobre o `par`. `agregado` é exposto + não exposto; Copa fica de fora dele.
CREATE TEMP TABLE recortado AS
SELECT 'agregado' AS recorte, * FROM par WHERE grupo IN ('exposto', 'nao_exposto')
UNION ALL
SELECT 'exposto', * FROM par WHERE grupo = 'exposto'
UNION ALL
SELECT 'copa_rateada', * FROM par WHERE grupo = 'copa_rateada';

-- 0. Sanidade: as duas células têm o mesmo universo de linhas (o JOIN acima é INNER — linha
--    que existe numa só sumiria calada).
SELECT
    (SELECT COUNT(*) FROM `{{ destino }}.ae200_celulas` WHERE celula = '{{ antes }}')  AS linhas_antes,
    (SELECT COUNT(*) FROM `{{ destino }}.ae200_celulas` WHERE celula = '{{ depois }}') AS linhas_depois,
    (SELECT COUNT(*) FROM par)                                                         AS linhas_pareadas;

-- 1. ACENDIMENTO por premissa (toda linha, com ou sem preço).
SELECT
    r.recorte,
    r.market,
    pa.premissa,
    COUNT(*)                                                             AS linhas,
    COUNTIF(pa.acendeu)                                                  AS acende_antes,
    COUNTIF(pd.acendeu)                                                  AS acende_depois,
    ROUND(100 * SAFE_DIVIDE(COUNTIF(pa.acendeu), COUNT(*)), 2)           AS taxa_antes_pct,
    ROUND(100 * SAFE_DIVIDE(COUNTIF(pd.acendeu), COUNT(*)), 2)           AS taxa_depois_pct,
    COUNTIF(pa.acendeu AND NOT COALESCE(pd.acendeu, FALSE))              AS apagou,
    COUNTIF(NOT COALESCE(pa.acendeu, FALSE) AND pd.acendeu)              AS acendeu
FROM recortado r,
    UNNEST(r.premissas_antes)  pa WITH OFFSET i,
    UNNEST(r.premissas_depois) pd WITH OFFSET j
WHERE i = j
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- 2. FAIXA — matriz de transição, só linhas com preço.
SELECT
    recorte,
    faixa_antes,
    faixa_depois,
    COUNT(*) AS linhas
FROM recortado
WHERE teve_preco
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- 3. O VEREDITO da (b) e o tamanho do Δ, só linhas com preço.
SELECT
    recorte,
    COUNT(DISTINCT fixture_id)                                                 AS fixtures,
    COUNT(*)                                                                   AS linhas_com_preco,
    COUNTIF(faixa_antes IS DISTINCT FROM faixa_depois)                          AS trocou_faixa,
    ROUND(100 * SAFE_DIVIDE(COUNTIF(faixa_antes IS DISTINCT FROM faixa_depois), COUNT(*)), 3)
                                                                               AS trocou_faixa_pct,
    COUNTIF(score_antes IS DISTINCT FROM score_depois)                          AS mudou_score,
    ROUND(AVG(score_depois - score_antes), 2)                                   AS delta_medio,
    MIN(score_depois - score_antes)                                             AS delta_min,
    MAX(score_depois - score_antes)                                             AS delta_max,
    SUM(sem_dado_depois) - SUM(sem_dado_antes)                                  AS delta_premissas_sem_dado,
    IF(recorte = 'agregado',
       IF(SAFE_DIVIDE(COUNTIF(faixa_antes IS DISTINCT FROM faixa_depois), COUNT(*)) < 0.01,
          'calibração intocada (< 1%)', 'pergunta ao PM (>= 1%)'),
       NULL)                                                                   AS veredito_b
FROM recortado
WHERE teve_preco
GROUP BY 1
ORDER BY 1;
