#!/bin/bash
# Carrega o NDJSON na tabela NATIVA smartbetting-dados.futebol_taskF.leva8_raw_fixtures, com o MESMO
# schema da external table de produção (futebol.raw_futebol_fixtures). ESCREVE só nessa tabela.
#
# NUNCA aponte isto para o bucket do landing nem para o dataset 'futebol'.
#
# uso: bash scripts/taskf_leva_ligas/03_carrega_raw_fixtures.sh [arquivo_ndjson]
set -u
P=smartbetting-dados
D=futebol_taskF
LOC=us-east1
BASE=${TASKF_LEVA_OUT:-/tmp/taskf_leva}
NDJSON=${1:-$BASE/leva8_raw_fixtures.ndjson}
SCHEMA=$BASE/raw_fixtures_schema.json

[ -f "$NDJSON" ] || { echo "não achei $NDJSON (rode 02_monta_ndjson.py antes)"; exit 2; }
mkdir -p "$BASE"

bq --location=$LOC show --schema --format=prettyjson $P:futebol.raw_futebol_fixtures > "$SCHEMA" || exit 3
bq --location=$LOC load --source_format=NEWLINE_DELIMITED_JSON --ignore_unknown_values --replace \
  --schema="$SCHEMA" $P:$D.leva8_raw_fixtures "$NDJSON" || exit 4

cat > "$BASE/confere_carga.sql" <<'EOF'
SELECT requested_league_id AS liga, requested_season AS temporada, COUNT(*) AS n,
       COUNT(DISTINCT fixture.id) AS n_ids, COUNTIF(fixture.timestamp IS NULL) AS sem_timestamp
FROM `smartbetting-dados.futebol_taskF.leva8_raw_fixtures`
GROUP BY 1, 2 ORDER BY 1, 2
EOF
echo "contagens por liga e temporada (n deve ser igual a n_ids; sem_timestamp deve ser 0):"
bq --location=$LOC query --use_legacy_sql=false --format=pretty --quiet < "$BASE/confere_carga.sql"
