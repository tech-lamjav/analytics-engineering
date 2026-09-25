{{ config(
    materialized='table',
    description='Entrega 3 do #147/#148 (AE#175, ADR 0016), estendida ao Handicap asiático pela AE#202. Achata insumos_medidos — ARRAY<STRUCT<premissa, insumo, valor FLOAT64>>, publicado em int_futebol_premissas_1x2 (AE#153, PR #154, ADR 0014), em int_futebol_premissas_ah (AE#202) em int_futebol_premissas_btts (AE#208) e em int_futebol_premissas_dc (AE#209) — a lista mora em futebol_mercados_com_insumos_medidos() (macros/premissas_valores_medidos.sql) e é a mesma que as duas guardas de reconstrução leem — em colunas escalares, pra atravessar o sync BQ->Postgres (src/sync/bq_to_postgres.py, data-engineering), que pula toda coluna REPEATED/RECORD. Uma linha por (fixture_id, outcome, market, line_value, premissa, insumo) que a premissa/penalidade aplica à linha; o WHERE premissa IS NOT NULL de futebol_insumos_medidos() já garante que não-aplicável não gera linha nenhuma antes do UNNEST. market/line_value entraram no grão desde a AE#175, com o 1X2 sozinho (ver ADR 0016 para o porquê: mudar grão de tabela já sincronizada, depois que ela já está em produção, é o defeito que já mordeu este repo quatro vezes). AE#202: o Handicap é o segundo mercado e o primeiro a POPULAR line_value — uma linha por linha de handicap, com o valor repetido entre elas. Os valores são estatística do time e não mudam com a linha, mas QUAIS premissas se aplicam muda (o mesmo Home é favorito em −0,5 e azarão em +0,5; na linha 0 a odd decide, B3); colapsar a linha obrigaria o front a reimplementar essa regra, que é o que a #147 existe para acabar. Custo aceito na #202: ~850 mil linhas a mais no Postgres. AE#208: o Ambos marcam volta ao grão do 1X2 — sem linha (line_value NULL), 8 entradas por saída Yes e 6 por No, ~150 mil linhas. AE#209: a Dupla chance também, 10 entradas por saída (1X e X2), ~220 mil linhas; os insumos x_* dela são o veredito de premissas do 1X2 e valem 1.0/0.0 — o número por trás está na linha match_winner do mesmo jogo, no lado coberto. Mesmo regime dos modelos de premissa: tabela full-refresh, recalculada a cada build, aprovado pelo Victor no ClickUp wdx6zf0fq2/wdx6zf0nnv ("fica no mesmo regime... e para nós tudo bem"). TEM de estar no --select de TODO workflow que reconstrói um dos pais (int_futebol_premissas_1x2, _ah, _btts ou _dc), senão a tabela servida fica defasada do pai e assert_insumos_medidos_reconstroi fica vermelha (FAIL 2792/94/46 em 20, 23 e 24/09). Hoje são dois, ambos no data-engineering: workflow_futebol_odds.yml (DE#85, 16/09, junto do allowlist do sync) e workflow_futebol.yml, o diário (DE#105, 24/09; o DE#85 só tinha mexido no de odds). Por isso, desde a AE#202, as duas guardas de reconstrução (tests/assert_insumos_medidos_reconstroi.sql e o unique_combination_of_columns de _fact_insumos_medidos.yml) levam tag:guarda — a condição que a AE#175 deixou escrita para ligá-las ("junto do PR que adicionar o modelo ao selector") foi cumprida no DE e ninguém tinha voltado aqui. A tag só ficou segura depois do DE#105: verde no diário e no de odds em 25/09 (AE#201).'
) }}

{#- Os mercados vêm de futebol_mercados_com_insumos_medidos() (AE#208), a mesma lista que as
    duas guardas de reconstrução leem: mercado novo lá entra aqui e nelas no mesmo ato.
    line_value só vem do modelo nos mercados com linha (Handicap: o handicap na ótica do
    MANDANTE, o mesmo valor que o funil e o board carregam, e o front casa por ele sem
    converter); nos outros é NULL, porque o mercado não tem linha. -#}
{%- set mercados = futebol_mercados_com_insumos_medidos() %}
WITH
{%- for m in mercados %}
premissas_{{ m.market_id }} AS (
    SELECT
        fixture_id,
        outcome,
        {{ 'line_value' if m.tem_linha else 'CAST(NULL AS FLOAT64) AS line_value' }},
        insumos_medidos
    FROM {{ ref(m.modelo) }}
){{ ',' if not loop.last }}
{%- endfor %}

{% for m in mercados -%}
SELECT
    p.fixture_id,
    p.outcome,
    '{{ futebol_mercados_pontuados()[m.market_id] }}' AS market,
    p.line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM premissas_{{ m.market_id }} AS p,
UNNEST(p.insumos_medidos) AS im
{%- if not loop.last %}

UNION ALL

{% endif %}
{%- endfor %}
