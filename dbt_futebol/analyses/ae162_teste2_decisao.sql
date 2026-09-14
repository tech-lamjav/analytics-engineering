{#
    AE#162 (spec #157) — incorpora "Decisão" (mata-mata OU reta final de liga com posição em
    jogo, lado Away) ao Teste 2 do handicap de escanteios, completando o catálogo de 10
    premissas do ClickUp wdx6zf1tt8.

    Protocolo declarado no comentário de pré-registro da issue #162, ANTES de qualquer query
    de ROI:
      - lado: só Away (Decisão é premissa do lado de baixo)
      - mata_mata: fact_fixtures.round fora de "Regular Season"/"Group Stage"/"League Stage"
      - reta_final: o visitante já jogou >= 80% das rodadas da fase de pontos corridos da
        própria temporada (fact_fixtures.round, informação de calendário, não look-ahead)
      - zona em disputa: futebol_zona_tabela_em_disputa() (AE#160) sobre a leitura de
        standings do visitante mais recente ANTES do apito (nunca a mais recente disponível
        hoje) — NULL antes de 11/06/2026 (início do histórico de standings)

    Mesma base/universo/gates/piso do #161 — este ticket só ACRESCENTA uma linha ao catálogo,
    não remede as outras 9.

    Rodar com:
      dbt compile --select ae162_teste2_decisao
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae162_teste2_decisao.sql
#}

WITH {{ ae161_base_escanteios(cutoff=none, janela_fixa=none, gates_do_board=true) }},

premissas_por_lado AS (
    {{ ae161_premissas_escanteios(tabela='apostas', incluir_decisao=true, incluir_peso_original=true) }}
),

janela AS (
    SELECT
        MIN(DATE(kickoff_utc)) AS janela_ini,
        MAX(DATE(kickoff_utc)) AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*) AS linhas_no_universo
    FROM apostas
),

agregado AS (
    SELECT
        pl.outcome_side                                         AS lado,
        pl.premissa,
        a.benchmark,
        COUNTIF(pl.acesa)                                       AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL))        AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL))        AS p_real,
        AVG(IF(pl.acesa, a.min_jogos, NULL))                    AS jogos_medios
    FROM premissas_por_lado pl
    JOIN apostas a
      ON  a.fixture_id    = pl.fixture_id
      AND a.outcome_side  = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
    GROUP BY lado, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
)

SELECT
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    j.linhas_no_universo,
    10                       AS premissas_no_catalogo,
    'Handicap de escanteios' AS mercado,
    g.lado,
    g.premissa,
    g.benchmark,
    (g.benchmark = 'pinnacle')                                  AS usado_para_peso,
    g.n,
    ROUND(SAFE_DIVIDE(g.n, g.n + 50), 2)                        AS fator_encolhimento,
    ROUND(g.jogos_medios, 1)                                    AS jogos_medios,
    ROUND(g.p_odd  * 100, 1)                                    AS a_odd_dava_pct,
    ROUND(g.p_real * 100, 1)                                    AS aconteceu_pct,
    ROUND((g.p_real - g.p_odd) * 100, 1)                        AS diferenca_pp,
    IF(g.benchmark = 'pinnacle',
       ROUND(GREATEST((g.p_real - g.p_odd) * 100, 0) * SAFE_DIVIDE(g.n, g.n + 50), 2),
       NULL)                                                    AS peso_medido,
    IF((g.p_real - g.p_odd) <= 0, 'ZERADA — sem ganho' , 'com ganho') AS veredito
FROM agregado g
CROSS JOIN janela j
ORDER BY g.lado, g.benchmark DESC, diferenca_pp DESC
