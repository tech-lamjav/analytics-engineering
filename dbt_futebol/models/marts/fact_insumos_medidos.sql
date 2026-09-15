{{ config(
    materialized='table',
    description='Entrega 3 do #147/#148 (AE#175, ADR 0016). Achata insumos_medidos — ARRAY<STRUCT<premissa, insumo, valor FLOAT64>>, publicado em int_futebol_premissas_1x2 pela Entrega 2 (AE#153, PR #154, ADR 0014) — em colunas escalares, pra atravessar o sync BQ->Postgres (src/sync/bq_to_postgres.py, data-engineering), que pula toda coluna REPEATED/RECORD. Uma linha por (fixture_id, outcome, premissa, insumo) que a premissa/penalidade aplica à linha; o WHERE premissa IS NOT NULL de futebol_insumos_medidos() já garante que não-aplicável não gera linha nenhuma antes do UNNEST. market/line_value entram no grão desde já, mesmo com o escopo travado no 1X2 (market=match_winner constante, line_value NULL) — ver ADR 0016 para o porquê: mudar grão de tabela já sincronizada, depois que ela já está em produção, é o defeito que já mordeu este repo quatro vezes (contrato de serving das RPCs). Mesmo regime de int_futebol_premissas_1x2: tabela full-refresh, recalculada a cada build, aprovado pelo Victor no ClickUp wdx6zf0fq2/wdx6zf0nnv ("fica no mesmo regime... e para nós tudo bem"). Fora desta entrega, em repos separados: a entrada no allowlist do sync (FUTEBOL_SYNC_TABLES_ORDERED, data-engineering), a migration que cria a tabela de destino no Postgres (prop-play-predictor — precisa existir ANTES do allowlist ir para produção, ou check_schema_parity acusa toda coluna como missing_in_pg), e o RPC de leitura pro front/placar (prop-play-predictor). ⚠️ ACHADO DO CODE-REVIEW: este modelo AINDA NÃO está no `--select` de workflow_futebol_odds.yml (data-engineering) — isso é o ticket do allowlist, deliberadamente separado. Por isso as duas guardas de reconstrução desta entrega (tests/assert_insumos_medidos_reconstroi.sql e o unique_combination_of_columns de _fact_insumos_medidos.yml) NASCEM SEM tag:guarda: marcá-las guarda agora faria a fase agendada `dbt test --select tag:guarda` do PRD quebrar contra uma tabela que o `dbt run` daquele workflow nunca constrói (a mesma classe de defeito que project_futebol_modelo_novo_precisa_selector.md documenta). A tag entra junto do PR que adicionar este modelo ao selector — não antes.'
) }}

SELECT
    p.fixture_id,
    p.outcome,
    '{{ futebol_mercados_pontuados()[1] }}' AS market,
    CAST(NULL AS FLOAT64) AS line_value,
    im.premissa,
    im.insumo,
    im.valor
FROM {{ ref('int_futebol_premissas_1x2') }} AS p,
UNNEST(p.insumos_medidos) AS im
