{{ config(
    materialized='table',
    description='Entrega 3 do #147/#148 (AE#175, ADR 0016), estendida ao Handicap asiático pela AE#202. Achata insumos_medidos — ARRAY<STRUCT<premissa, insumo, valor FLOAT64>>, publicado em int_futebol_premissas_1x2 (AE#153, PR #154, ADR 0014) e em int_futebol_premissas_ah (AE#202) — em colunas escalares, pra atravessar o sync BQ->Postgres (src/sync/bq_to_postgres.py, data-engineering), que pula toda coluna REPEATED/RECORD. Uma linha por (fixture_id, outcome, market, line_value, premissa, insumo) que a premissa/penalidade aplica à linha; o WHERE premissa IS NOT NULL de futebol_insumos_medidos() já garante que não-aplicável não gera linha nenhuma antes do UNNEST. market/line_value entraram no grão desde a AE#175, com o 1X2 sozinho (ver ADR 0016 para o porquê: mudar grão de tabela já sincronizada, depois que ela já está em produção, é o defeito que já mordeu este repo quatro vezes). AE#202: o Handicap é o segundo mercado e o primeiro a POPULAR line_value — uma linha por linha de handicap, com o valor repetido entre elas. Os valores são estatística do time e não mudam com a linha, mas QUAIS premissas se aplicam muda (o mesmo Home é favorito em −0,5 e azarão em +0,5; na linha 0 a odd decide, B3); colapsar a linha obrigaria o front a reimplementar essa regra, que é o que a #147 existe para acabar. Custo aceito na #202: ~850 mil linhas a mais no Postgres. Mesmo regime dos modelos de premissa: tabela full-refresh, recalculada a cada build, aprovado pelo Victor no ClickUp wdx6zf0fq2/wdx6zf0nnv ("fica no mesmo regime... e para nós tudo bem"). Está no --select dos dois workflows que reconstroem os pais (workflow_futebol.yml e workflow_futebol_odds.yml, data-engineering, DE#85 em 16/09) e no allowlist do sync; por isso, desde a AE#202, as duas guardas de reconstrução (tests/assert_insumos_medidos_reconstroi.sql e o unique_combination_of_columns de _fact_insumos_medidos.yml) levam tag:guarda — a condição que a AE#175 deixou escrita para ligá-las ("junto do PR que adicionar o modelo ao selector") foi cumprida no DE e ninguém tinha voltado aqui.'
) }}

WITH premissas_1x2 AS (
    SELECT fixture_id, outcome, insumos_medidos
    FROM {{ ref('int_futebol_premissas_1x2') }}
),

-- AE#202: Handicap asiático. line_value é o handicap na ótica do MANDANTE, o mesmo valor que o
-- funil e o board carregam — o front casa por ele sem converter.
premissas_ah AS (
    SELECT fixture_id, outcome, line_value, insumos_medidos
    FROM {{ ref('int_futebol_premissas_ah') }}
)

SELECT
    p.fixture_id,
    p.outcome,
    '{{ futebol_mercados_pontuados()[1] }}' AS market,
    CAST(NULL AS FLOAT64) AS line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM premissas_1x2 AS p,
UNNEST(p.insumos_medidos) AS im

UNION ALL

SELECT
    p.fixture_id,
    p.outcome,
    '{{ futebol_mercados_pontuados()[4] }}' AS market,
    p.line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM premissas_ah AS p,
UNNEST(p.insumos_medidos) AS im
