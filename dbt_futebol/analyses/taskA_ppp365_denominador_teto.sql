{#
    PPP#365 — TROCAR O DENOMINADOR DO SCORE NORMALIZADO: p95 → TETO DE PONTOS.

    Issue: prop-play-predictor#365 ("Score: o 100 é teto do clamp e convive com premissas
    fora do corte"). Aberta pelo Victor, cc @MateusKasuya. Mede o efeito de trocar o
    denominador de `futebol_score_normalizado()` (macro em macros/futebol_score_normalizado.sql)
    do p95 congelado (seed `futebol_p95_nota_contexto`) para o TETO DE PONTOS do catálogo —
    a soma dos pesos máximos de cada (mercado, lado).

    Rodar com:
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_ppp365_denominador_teto
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/taskA_ppp365_denominador_teto.sql

    ──────────────────────────────────────────────────────────────────────────────────────
    O TETO NÃO É RECALCULADO AQUI — É COPIADO DA A6 (#105), JÁ CONFERIDO

    `dbt_futebol/analyses/taskA_a6_p95.sql` já carrega esses onze valores na coluna
    `teto_catalogo`, verificados contra os pesos escritos nos cinco modelos
    `int_futebol_premissas_*.sql` (ex.: 1X2 Home = 12+8+8+8+6+5+4 = 51, a soma de TODOS os
    pesos daquele lado em `int_futebol_premissas_1x2.sql`). Reescrever essa conta aqui seria
    ter duas fontes do mesmo número; este arquivo importa o resultado, não o refaz.

    ⚠️ TETO ≠ MÁXIMO OBSERVADO. Conferido em produção (04/09): o máximo de `pts_premissas`
    já visto no funil para 1X2/Home é 43, não 51 — nenhuma linha histórica teve as sete
    premissas acesas ao mesmo tempo (o gap de 8 é exatamente o peso de `desfalque_adversario`
    ou de `superioridade_tabela`, que tendem a não coincidir com as outras). Usar o máximo
    observado em vez do teto declarado subestimaria o denominador e reintroduziria parte do
    mesmo problema que esta troca quer resolver. Para AH/Azarao e BTTS/No, p95 já É o teto —
    são os dois lados que a B3 (wdx6zev656) chamou de "os únicos sinais fortes que não
    dependem de amostra curta", e o desenho já não os deixava saturar.

    ──────────────────────────────────────────────────────────────────────────────────────
    POR QUE MEDIR NO BOARD (`passou_no_gate`) NÃO É VIÉS AQUI

    A `taskA_a6_p95.sql` mediu sobre o funil inteiro, nunca sobre o board, porque antes da
    virada (#109) o board era filtrado por `score >= 40` — medir a distribuição da nota em
    cima de quem já passou pela nota mediria um recorte da própria coisa. Isso mudou: desde
    a virada, `passou_no_gate` é só qualidade de dado (cobertura, liquidez, outlier, faixa de
    odd), sem corte de nota nenhum. O board de hoje não é mais amostra enviesada por score,
    então medir nele responde exatamente a pergunta do PPP#365: "o que o assinante vê hoje".
    Este arquivo mede as duas populações — board e funil inteiro — e as duas concordam na
    direção do efeito.

    ──────────────────────────────────────────────────────────────────────────────────────
    O CORTE DE FAIXA PROPOSTO (30/60 → 24/47)

    Não é ROI remedido (isso é outra medição, do porte da A4/#107) — é o corte que reproduz,
    sobre `score_v2`, a MESMA proporção Baixa/Média/Alta que 30/60 produz hoje sobre
    `score_normalizado` no board. A razão bate com a queda média da nota (41,1 → 33,5, fator
    ~1,227): 30/1,227 ≈ 24,4 e 60/1,227 ≈ 48,9, e os percentis batem em 24/47. Serve como
    ponto de partida; se o Victor quiser a régua reancorada em ROI (como a A4 fez para
    30/60), é medição própria, não esta.
#}

WITH teto AS (
    SELECT * FROM UNNEST([
        STRUCT('{{ futebol_mercados_pontuados()[1] }}' AS market, 'Home'     AS lado, 51 AS teto),
        STRUCT('{{ futebol_mercados_pontuados()[1] }}',           'Away',        47),
        STRUCT('{{ futebol_mercados_pontuados()[1] }}',           'Draw',         0),
        STRUCT('{{ futebol_mercados_pontuados()[5] }}',           'Over',        50),
        STRUCT('{{ futebol_mercados_pontuados()[5] }}',           'Under',       46),
        STRUCT('{{ futebol_mercados_pontuados()[4] }}',           'Favorito',    40),
        STRUCT('{{ futebol_mercados_pontuados()[4] }}',           'Azarao',      30),
        STRUCT('{{ futebol_mercados_pontuados()[4] }}',           'Pick',         0),
        STRUCT('{{ futebol_mercados_pontuados()[8] }}',           'Yes',         34),
        STRUCT('{{ futebol_mercados_pontuados()[8] }}',           'No',          28),
        STRUCT('{{ futebol_mercados_pontuados()[12] }}',          'unico',       34)
    ])
),

recalculado AS (
    SELECT
        f.market,
        f.lado,
        f.passou_no_gate,
        f.nota_contexto,
        f.score_normalizado AS score_p95,
        t.teto,
        CASE
            WHEN f.nota_contexto IS NULL THEN NULL
            WHEN t.teto IS NULL OR t.teto <= 0 THEN 0
            ELSE LEAST(100, CAST(ROUND(f.nota_contexto / t.teto * 100) AS INT64))
        END AS score_v2
    FROM {{ ref('fact_value_funnel') }} f
    JOIN teto t USING (market, lado)
    WHERE f.janela_e_corrente
      AND f.score_normalizado IS NOT NULL
)

SELECT
    IF(passou_no_gate, 'board_publicado', 'funil_inteiro') AS populacao,
    market,
    lado,
    COUNT(*)                                              AS n,
    ROUND(100 * COUNTIF(score_p95 = 100) / COUNT(*), 1)   AS pct_no_teto_com_p95,
    ROUND(100 * COUNTIF(score_v2  = 100) / COUNT(*), 1)   AS pct_no_teto_com_teto,
    ROUND(AVG(score_p95), 1)                              AS media_p95,
    ROUND(AVG(score_v2), 1)                                AS media_teto,
    COUNTIF(score_v2 < 24)                                AS baixa_corte_24_47,
    COUNTIF(score_v2 BETWEEN 24 AND 46)                   AS media_corte_24_47,
    COUNTIF(score_v2 >= 47)                               AS alta_corte_24_47
FROM recalculado
GROUP BY GROUPING SETS (
    (populacao, market, lado),
    (populacao)
)
ORDER BY populacao DESC, market, lado
