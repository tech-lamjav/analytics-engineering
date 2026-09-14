{#
    AE#161 (spec #157) — REPRODUÇÃO da simulação ad-hoc do Victor (Postgres, seção 6 de
    docs/futebol-metodologia-de-premissas.md / ClickUp wdx6zf1tt8), dentro da tolerância
    declarada no comentário de pré-registro da issue #161 (postado ANTES desta análise).

    Protocolo (fixado no pré-registro, não decidido aqui):
      cutoff = 2026-09-10 (a data que o documento declara)
      janela = t24h fixa (não a corrente)
      gates do board = OFF (não existiam quando a medição original rodou)
      liquidez mínima = 3 casas (o "mínimo de três casas" do universo declarado)
      só linha meia, melhor odd, aposta de 1 unidade (lucro = odd-1 se ganhou, -1 senão)

    PORTA 1 (universo): jogos e linhas dentro de ±10% relativo de 373/1.464. Se qualquer um
    dos dois estourar, a reprodução NÃO passa e o resultado a reportar é a divergência de
    universo — comparar ROI de duas populações de tamanho diferente não prova nada.

    PORTA 2 (só se a porta 1 passar): ROI geral e por lado dentro de ±3pp absolutos de
    −3,77% / +1,09% (casa) / −8,64% (fora).

    Rodar com:
      dbt compile --select ae161_reproducao_simulacao
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae161_reproducao_simulacao.sql
#}

WITH {{ ae161_base_escanteios(cutoff='2026-09-10', janela_fixa='t24h', gates_do_board=false, liquidez_min_casas=3) }},

universo AS (
    SELECT
        COUNT(*)                       AS linhas,
        COUNT(DISTINCT fixture_id)     AS jogos,
        373                             AS jogos_declarados,
        1464                            AS linhas_declaradas
    FROM apostas
),

roi_geral AS (
    SELECT
        'geral' AS recorte,
        COUNT(*)                                              AS n,
        ROUND(AVG(IF(ganhou, best_odd - 1, -1)) * 100, 2)      AS roi_pct,
        -3.77                                                  AS roi_declarado
    FROM apostas
),

roi_por_lado AS (
    SELECT
        CASE outcome_side WHEN 'Home' THEN 'lado casa' WHEN 'Away' THEN 'lado fora' END AS recorte,
        COUNT(*)                                              AS n,
        ROUND(AVG(IF(ganhou, best_odd - 1, -1)) * 100, 2)      AS roi_pct,
        CASE outcome_side WHEN 'Home' THEN 1.09 WHEN 'Away' THEN -8.64 END AS roi_declarado
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
