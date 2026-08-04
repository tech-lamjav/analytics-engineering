{#
    Task [0.1] — SEAM 1: reconciliação por resposta conhecida.  Ticket #4, spec #3.

    Roda a máquina GENERALIZADA (`task01_base`) restrita ao escopo que já foi publicado
    e mostra esperado vs obtido. Verde significa duas coisas, e as duas são necessárias
    antes de qualquer análise a jusante:

      1. generalizar para os 5 mercados não quebrou a lógica de gate nem de liquidação;
      2. as tabelas de premissa e odds são ESTÁVEIS entre rebuilds — nunca verificado,
         e toda conclusão histórica depende disso. Quando (2) falha, quem separa as
         hipóteses é `task01_estabilidade.sql`, não esta análise.

    Divergência não é necessariamente bug: pode ser instabilidade de tabela. As duas
    hipóteses são separáveis pelo `n` que vai ao lado de cada linha — valor diferente
    com amostra igual é lógica; amostra diferente é universo.

    Corte congelado em 2026-08-02, que é a janela dos números publicados (16/06 a 02/08).

    → RESULTADOS DAS EXECUÇÕES: `docs/TASK01_RESULTADOS.md`. Não moram aqui de
      propósito: este arquivo deve mudar quando a LÓGICA muda, não quando os números
      mudam.

    POR QUE ISTO NÃO É UM `tests/assert_*.sql`, apesar de ter cara de asserção: fixa uma
    data congelada e valores literais publicados, então apodrece por construção — em
    semanas passaria a falhar pelo motivo certo na hora errada. E o pipeline agendado
    roda `dbt run`, não `dbt build`, então não executaria ali de qualquer forma. O custo
    dessa escolha é real e assumido: nada re-executa isto sozinho, é rodar à mão.

    Rodar com:
      dbt compile --select task01_reconciliacao
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_reconciliacao.sql
#}

WITH {{ task01_base(cutoff='2026-08-02') }},

{#- PROCEDÊNCIA das constantes `esperado` deste bloco: tabela "Do Teste 3, a linha que
    muda a leitura é a do universo sem porta" na descrição da task [0.1] (ClickUp
    wdx6zevfgf), reproduzida na issue #3. -#}
teste3 AS (
    SELECT 'Teste 3' AS bloco, 'a. universo sem porta' AS metrica,
           COUNT(*) AS n, -10.2 AS esperado,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM apostas

    UNION ALL
    SELECT 'Teste 3', 'b. 2+ premissas',
           COUNT(*), -7.6,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE n_prem >= 2

    UNION ALL
    SELECT 'Teste 3', 'c. 3+ premissas',
           COUNT(*), -6.0,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE n_prem >= 3

    UNION ALL
    SELECT 'Teste 3', 'd. regra de hoje (edge > 0)',
           COUNT(*), -12.3,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE edge > 0

    UNION ALL
    SELECT 'Teste 3', 'e. edge > 0 e 2+ premissas',
           COUNT(*), -15.4,
           ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1)
    FROM apostas WHERE edge > 0 AND n_prem >= 2
),

{#- PROCEDÊNCIA: comentário de entrega da Task [0] no ClickUp wdx6zev64w — "Por mercado,
    todos viram: 1X2 +33,7 -> −2,5 · BTTS +25,9 -> −1,1 · Handicap +10,7 -> −9,9 · Gols
    +5,7 -> −7,3 · Dupla Chance +1,4% em 154 apostas". São os valores DEPOIS (base limpa),
    na porta 2+ premissas. Não constam da issue #4; entram porque localizam a deriva —
    se só um mercado se mover, a instabilidade tem endereço. -#}
teste3_mercado AS (
    SELECT
        'Teste 3 por mercado (2+)' AS bloco,
        m.rotulo AS metrica,
        COUNT(*) AS n,
        ANY_VALUE(m.esperado) AS esperado,
        ROUND((SUM(IF(a.ganhou, a.best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM apostas AS a
    JOIN UNNEST([
        STRUCT(1  AS market_id, 'a. 1X2'          AS rotulo, -2.5 AS esperado),
        STRUCT(5  AS market_id, 'b. Gols'         AS rotulo, -7.3 AS esperado),
        STRUCT(4  AS market_id, 'c. Handicap'     AS rotulo, -9.9 AS esperado),
        STRUCT(8  AS market_id, 'd. BTTS'         AS rotulo, -1.1 AS esperado),
        STRUCT(12 AS market_id, 'e. Dupla Chance' AS rotulo,  1.4 AS esperado)
    ]) AS m
      ON m.market_id = a.market_id
    WHERE a.n_prem >= 2
    GROUP BY m.rotulo
),

{#- Teste 2 do mercado de Gols, contra benchmark sharp (o mesmo filtro da rodada
    anterior, que exigia valor_fonte='pinnacle'). Métrica: acerto médio menos prob justa
    média, nas linhas em que a premissa acendeu.

    PROCEDÊNCIA: mesmo comentário de entrega da Task [0] — "Só clean_sheets_altos
    (+16,9) e defesas_firmes (+3,4) seguem positivos … xg_combinado_alto vai de +3,1
    para −2,6 · ataque_combinado +15,9 -> −3,6 · defesas_vazaveis +9,5 -> −5,2 ·
    ambos_vazam +4,4 -> −3,7". -#}
teste2_gols AS (
    SELECT
        'Teste 2 (Gols)' AS bloco,
        pl.premissa      AS metrica,
        COUNTIF(pl.acesa) AS n,
        e.esperado,
        ROUND((AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL))
             - AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL))) * 100, 1) AS obtido
    FROM apostas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    JOIN UNNEST([
        STRUCT('clean_sheets_altos' AS premissa,  16.9 AS esperado),
        STRUCT('defesas_firmes'     AS premissa,   3.4 AS esperado),
        STRUCT('xg_combinado_alto'  AS premissa,  -2.6 AS esperado),
        STRUCT('ataque_combinado'   AS premissa,  -3.6 AS esperado),
        STRUCT('defesas_vazaveis'   AS premissa,  -5.2 AS esperado),
        STRUCT('ambos_vazam'        AS premissa,  -3.7 AS esperado)
    ]) AS e
      ON e.premissa = pl.premissa
    WHERE a.market_id = 5
      AND a.benchmark = 'sharp'
    GROUP BY 1, 2, 4
),

cobertura AS (
    SELECT 'Cobertura' AS bloco,
           'a. jogos que sobreviveram a todos os recortes' AS metrica,
           COUNT(*) AS n, 168.0 AS esperado,
           CAST(COUNT(DISTINCT fixture_id) AS FLOAT64) AS obtido
    FROM apostas

    -- Se isto não for zero, a degradação graciosa falhou em algum lugar: contar
    -- premissas por SUM(CAST(bool AS INT64)) (a query original) propaga NULL e derruba
    -- a linha inteira de toda porta, enquanto COUNTIF não. Aí o número publicado não é
    -- reproduzível por construção, e não por erro meu.
    UNION ALL
    SELECT 'Cobertura', 'b. linhas com premissa NULL',
           COUNT(*), 0.0,
           CAST(SUM(n_prem_null) AS FLOAT64)
    FROM apostas
),

{#- GUARDA DE DESCARTE SILENCIOSO.

    Lê `odds`, que o macro deixa exposto SEM recorte nenhum — de propósito. A primeira
    versão desta guarda lia a fonte já filtrada por escopo, e portanto era cega
    exatamente à classe de perda que ela mesma tinha acabado de encontrar (as 3.642
    linhas do mercado 6). Guarda que só enxerga depois do filtro não guarda o filtro.

    Todo descarte é classificado por motivo. Os declarados são informativos; o que
    sobra tem de ser ZERO, e essa linha é emitida sempre, mesmo valendo zero — ausência
    de linha não pode ser confundida com ausência de checagem. -#}
descartes AS (
    SELECT
        CASE
            WHEN o.market_id NOT IN ({{ task01_markets().keys() | join(', ') }})
                THEN 'a. fora do escopo do Motor (declarado)'
            WHEN o.best_odd IS NULL OR o.edge IS NULL
                THEN 'b. sem preco justo, edge NULL (declarado)'
            WHEN NOT {{ task01_meia_linha('o.') }}
                THEN 'c. linha inteira, push possivel (declarado)'
            WHEN o.market_id = 12 AND o.outcome_side = '12'
                THEN 'd. gap conhecido: DC nao emite premissa p/ 12'
            ELSE
                 'e. INESPERADO'
        END AS motivo
    FROM odds AS o
    JOIN jogos_encerrados AS j
      ON j.fixture_id = o.fixture_id
    LEFT JOIN apostas AS ap
      ON  ap.market_id                  = o.market_id
      AND ap.fixture_id                 = o.fixture_id
      AND ap.outcome_side               = o.outcome_side
      AND COALESCE(ap.line_value, -999) = COALESCE(o.line_value, -999)
    WHERE ap.fixture_id IS NULL
),

descarte_assercao AS (
    SELECT 'Descarte' AS bloco,
           'z. INESPERADOS (tem de ser 0)' AS metrica,
           COUNT(*) AS n,
           0.0 AS esperado,
           CAST(COUNTIF(motivo = 'e. INESPERADO') AS FLOAT64) AS obtido
    FROM descartes
),

descarte_detalhe AS (
    SELECT 'Descarte' AS bloco, motivo AS metrica,
           COUNT(*) AS n, CAST(NULL AS FLOAT64) AS esperado,
           CAST(COUNT(*) AS FLOAT64) AS obtido
    FROM descartes GROUP BY motivo
),

{#- Informativo: onde procurar, se algo acima divergir. Agrupa POR benchmark, não
    ANY_VALUE(benchmark): os mercados 4 e 5 são MISTOS (a Pinnacle cobre a maior parte,
    mas não todos os jogos), e um rótulo arbitrário por mercado esconderia exatamente a
    distinção que esta task existe para tornar visível. -#}
por_benchmark AS (
    SELECT
        'Cobertura por benchmark' AS bloco,
        CONCAT('market ', CAST(market_id AS STRING), ' — ', benchmark) AS metrica,
        COUNT(*) AS n,
        CAST(NULL AS FLOAT64) AS esperado,
        ROUND((SUM(IF(ganhou, best_odd, 0)) / COUNT(*) - 1) * 100, 1) AS obtido
    FROM apostas
    GROUP BY market_id, benchmark
)

SELECT
    bloco,
    metrica,
    n,
    esperado,
    obtido,
    ROUND(obtido - esperado, 1) AS delta,
    -- 0,05 é tolerância de ARREDONDAMENTO e nada mais: os valores publicados têm 1 casa
    -- decimal, então reprodução exata dá delta 0,0. Não há faixa intermediária de
    -- propósito — uma banda larga o bastante p/ acomodar "quase igual" teria engolido a
    -- deriva de 0,4pp do Gols, que é o achado do ticket.
    CASE
        WHEN esperado IS NULL              THEN '—'
        WHEN ABS(obtido - esperado) < 0.05 THEN 'OK'
        ELSE                                    'DIVERGE'
    END AS status
FROM (
    SELECT * FROM teste3
    UNION ALL SELECT * FROM teste3_mercado
    UNION ALL SELECT * FROM teste2_gols
    UNION ALL SELECT * FROM cobertura
    UNION ALL SELECT * FROM descarte_assercao
    UNION ALL SELECT * FROM descarte_detalhe
    UNION ALL SELECT * FROM por_benchmark
)
ORDER BY bloco, metrica
