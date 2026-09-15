{#
    AE#183 (spec #179) — REPRODUÇÃO da simulação original do Total de escanteios (market_id 45),
    `prop-play-predictor` commit b89fadb, scripts/futebol-escanteios-total.mjs — dentro da
    tolerância declarada no comentário de pré-registro da issue #183 (postado ANTES desta
    análise, e ANTES da contagem preliminar de universo que já foi rodada e reportada lá).

    Protocolo (fixado no pré-registro, lido do CÓDIGO original, não só da prosa do documento):
      cutoff = 2026-09-12 (a data que o documento declara: "406 jogos... até 12/09/2026")
      janela = t24h fixa (collection_window='t24h' na query odds() do script)
      gates_do_board = OFF (não existiam quando a medição original rodou)
      liquidez mínima = 3 casas (count(distinct bookmaker_id) >= 3)
      linha meia + linha principal (gate primeiro, seleção depois — ver macro)
      métrica: ROI sobre best_odd (o script nunca lê de-vig/prob_justa — sem benchmark)

    PORTA 1 (universo): jogos e linhas dentro de ±10% relativo de 406/812. JÁ SABIDO, pela
    contagem preliminar do pré-registro: 589/1.178 medido, +45%/+45% — fora da porta.

    PORTA 2 (só por completude, dado que a porta 1 já falhou): ROI geral e por lado dentro de
    ±3pp absolutos de −3,41% (geral) / −1,37% (Mais) / −5,46% (Menos).

    Rodar com:
      dbt compile --select ae183_reproducao_simulacao
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae183_reproducao_simulacao.sql
#}

WITH {{ ae183_base_escanteios_total(cutoff='2026-09-12', janela_fixa='t24h', gates_do_board=false, liquidez_min_casas=3) }},

universo AS (
    SELECT
        COUNT(*)                       AS linhas,
        COUNT(DISTINCT fixture_id)     AS jogos,
        406                             AS jogos_declarados,
        812                             AS linhas_declaradas
    FROM apostas
),

-- ROI sobre odd crua, réplica de `roi()` do script: lucro = odd-1 se ganhou, -1 senão.
-- 'lado' aqui é outcome_side (Over/Under = Mais/Menos), a aposta REAL — não o lado_medido
-- de um catálogo (esta CTE não usa o catálogo de premissas, é só liquidação bruta).
roi_geral AS (
    SELECT
        'geral' AS recorte,
        COUNT(*)                                              AS n,
        ROUND(AVG(IF(ganhou, best_odd - 1, -1)) * 100, 2)      AS roi_pct,
        -3.41                                                  AS roi_declarado
    FROM apostas
),

roi_por_lado AS (
    SELECT
        CASE outcome_side WHEN 'Over' THEN 'lado Mais' WHEN 'Under' THEN 'lado Menos' END AS recorte,
        COUNT(*)                                              AS n,
        ROUND(AVG(IF(ganhou, best_odd - 1, -1)) * 100, 2)      AS roi_pct,
        CASE outcome_side WHEN 'Over' THEN -1.37 WHEN 'Under' THEN -5.46 END AS roi_declarado
    FROM apostas
    GROUP BY outcome_side
),

roi AS (
    SELECT * FROM roi_geral
    UNION ALL
    SELECT * FROM roi_por_lado
)

SELECT
    'universo' AS bloco,
    NULL AS recorte,
    u.jogos AS n_jogos,
    u.linhas AS n,
    NULL AS roi_pct,
    NULL AS roi_declarado,
    NULL AS diferenca_pp,
    CASE
        WHEN ABS(u.jogos  - u.jogos_declarados)  > 0.10 * u.jogos_declarados
          OR ABS(u.linhas - u.linhas_declaradas) > 0.10 * u.linhas_declaradas
        THEN CONCAT('NÃO REPRODUZ (porta 1): declarado ', CAST(u.jogos_declarados AS STRING),
                     ' jogos / ', CAST(u.linhas_declaradas AS STRING),
                     ' linhas; medido ', CAST(u.jogos AS STRING), ' / ', CAST(u.linhas AS STRING))
        ELSE 'dentro da porta 1 (±10%)'
    END AS veredito
FROM universo u

UNION ALL

SELECT
    'roi' AS bloco,
    r.recorte,
    NULL AS n_jogos,
    r.n,
    r.roi_pct,
    r.roi_declarado,
    ROUND(r.roi_pct - r.roi_declarado, 2) AS diferenca_pp,
    CASE
        WHEN ABS(r.roi_pct - r.roi_declarado) > 3.0
        THEN 'NÃO REPRODUZ (porta 2, >3pp)'
        ELSE 'dentro da porta 2 (±3pp)'
    END AS veredito
FROM roi r
ORDER BY bloco, recorte
