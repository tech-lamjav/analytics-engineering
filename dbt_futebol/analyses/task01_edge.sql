{#
    Task [0.1] — VARREDURA DE EDGE.  Ticket #7 (Pedido 3 da task), spec #3.

    A pergunta do Pedido 3: barrar linha cujo preço está muito pior que o justo muda o
    ROI, ou é neutro? Se for neutro, o filtro proposto na A3 é proteção de reputação e
    não de performance.

    O número que justificava aquele filtro foi medido na BASE CONTAMINADA (a regra
    testada era "2 premissas mais limite de preço"), então morreu junto com o resto.

    ────────────────────────────────────────────────────────────────────────────────
    Por que decil e não dois pontos: a tabela do Teste 3 já mostra que preço COMO PORTA
    piora — exigir edge positivo dá −12,3% contra −10,2% de apostar tudo. O Pedido 3
    pergunta pela cauda OPOSTA. As duas podem ser verdade ao mesmo tempo: a relação
    entre preço e retorno não precisa ser monótona, e dois pontos soltos não mostram o
    formato dela.

    Este ticket não consome peso nenhum, então é independente dos Testes 2 e 4.
    ────────────────────────────────────────────────────────────────────────────────
    Duas quebras acompanham cada corte, pelo que os tickets anteriores acharam:

    · PISO DE AMOSTRA — no Teste 2 o piso inverteu os três maiores sinais. Se ele também
      mexer aqui, "preço não seleciona" pode ser efeito de composição e não de preço.
    · BENCHMARK — o edge é calculado contra a prob justa, e a fonte dela muda por
      mercado. No Handicap o ROI das linhas sharp é −6,5 e o das consenso é −26,7. Um
      corte de edge aplicado ao conjunto todo é, em parte, um corte de benchmark
      disfarçado.

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_edge
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_edge.sql
#}

WITH {{ task01_base() }},

{#- EXCLUSÃO OBRIGATÓRIA aqui: as linhas de conjunto incompleto têm prob_justa = 1,0 por
    construção, logo edge = odd − 1. Elas não são medições de valor, são um artefato do
    de-vig de consenso, e ficam INTEIRAS no topo da distribuição de edge — deixá-las
    dentro tornaria a varredura de edge uma varredura do artefato. São 172 linhas com 2
    vitórias em 172 e ROI −35,5%.

    O bloco D abaixo mede o tamanho do que foi tirado, para que a exclusão seja auditável
    e não silenciosa. -#}
apostas_validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

com_decil AS (
    SELECT
        a.*,
        NTILE(10) OVER (ORDER BY a.edge) AS decil
    FROM apostas_validas AS a
),

{#- Decis do edge sobre o universo inteiro. A coluna de piso 5 mede DENTRO das mesmas
    fronteiras de decil — reparticionar o conjunto filtrado daria decis diferentes e as
    duas colunas deixariam de ser comparáveis. -#}
decis AS (
    SELECT
        'A. decil de edge'                                          AS bloco,
        CONCAT('decil ', LPAD(CAST(decil AS STRING), 2, '0'))        AS corte,
        ROUND(MIN(edge) * 100, 1)                                   AS edge_min,
        ROUND(MAX(edge) * 100, 1)                                   AS edge_max,
        COUNT(*)                                                    AS n_p0,
        ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS roi_p0,
        COUNTIF(min_jogos >= 5)                                     AS n_p5,
        ROUND(SAFE_DIVIDE(SUM(IF(ganhou AND min_jogos >= 5, best_odd, 0)),
                          COUNTIF(min_jogos >= 5)) * 100 - 100, 1)  AS roi_p5
    FROM com_decil
    GROUP BY decil
),

{#- Cortes nomeados. O primeiro é o universo sem filtro (referência), e os seguintes vão
    afrouxando o piso de edge até a regra de hoje. -#}
cortes AS (
    {%- set limites = [
        ('a. sem filtro (referencia)',      -999.0),
        ('b. edge > -30%',                    -0.30),
        ('c. edge > -20%',                    -0.20),
        ('d. edge > -10%',                    -0.10),
        ('e. edge >  -5%',                    -0.05),
        ('f. edge >   0%  (regra de hoje)',    0.00)
    ] -%}
    {%- for rotulo, lim in limites %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        'B. corte de edge' AS bloco,
        '{{ rotulo }}'     AS corte,
        ROUND(MIN(edge) * 100, 1)                                   AS edge_min,
        ROUND(MAX(edge) * 100, 1)                                   AS edge_max,
        COUNT(*)                                                    AS n_p0,
        ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS roi_p0,
        COUNTIF(min_jogos >= 5)                                     AS n_p5,
        ROUND(SAFE_DIVIDE(SUM(IF(ganhou AND min_jogos >= 5, best_odd, 0)),
                          COUNTIF(min_jogos >= 5)) * 100 - 100, 1)  AS roi_p5
    FROM apostas_validas
    WHERE edge > {{ lim }}
    {%- endfor %}
),

{#- O mesmo corte, quebrado por benchmark: separa "o preço seleciona" de "a Pinnacle
    escolhe quais jogos precificar". -#}
por_benchmark AS (
    SELECT
        'C. benchmark'                                              AS bloco,
        CONCAT(benchmark, faixa)                                    AS corte,
        ROUND(MIN(edge) * 100, 1)                                   AS edge_min,
        ROUND(MAX(edge) * 100, 1)                                   AS edge_max,
        COUNT(*)                                                    AS n_p0,
        ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS roi_p0,
        COUNTIF(min_jogos >= 5)                                     AS n_p5,
        ROUND(SAFE_DIVIDE(SUM(IF(ganhou AND min_jogos >= 5, best_odd, 0)),
                          COUNTIF(min_jogos >= 5)) * 100 - 100, 1)  AS roi_p5
    FROM (
        SELECT *, IF(edge > 0, ' · edge > 0', ' · tudo') AS faixa
        FROM apostas_validas
    )
    GROUP BY benchmark, faixa
),

{#- Auditoria da exclusão: o que foi tirado dos blocos A-C, para a exclusão não ser
    silenciosa. Espera-se ROI muito ruim e edge absurdo — é a assinatura do artefato. -#}
descartado AS (
    SELECT 'D. excluido do bloco A-C' AS bloco,
           'conjunto de saidas incompleto' AS corte,
           ROUND(MIN(edge) * 100, 1) AS edge_min, ROUND(MAX(edge) * 100, 1) AS edge_max,
           COUNT(*) AS n_p0,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS roi_p0,
           COUNTIF(min_jogos >= 5) AS n_p5,
           ROUND(SAFE_DIVIDE(SUM(IF(ganhou AND min_jogos >= 5, best_odd, 0)),
                             COUNTIF(min_jogos >= 5)) * 100 - 100, 1) AS roi_p5
    FROM apostas WHERE conjunto_incompleto
)

SELECT * FROM decis
UNION ALL SELECT * FROM cortes
UNION ALL SELECT * FROM por_benchmark
UNION ALL SELECT * FROM descartado
ORDER BY bloco, corte
