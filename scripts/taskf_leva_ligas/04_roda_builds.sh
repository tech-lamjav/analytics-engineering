#!/bin/bash
# Mede o efeito retroativo (PIT) das ligas AR/CO/PE/MX no futebol_taskF: 3 builds (cenários
# '2025_2026', '2026' e baseline 'antes'), um snapshot de cada, e RESTAURAÇÃO EXATA do taskF.
#
# uso:  bash scripts/taskf_leva_ligas/04_roda_builds.sh checagens   -> SÓ LEITURA
#       bash scripts/taskf_leva_ligas/04_roda_builds.sh completo    -> builds + snapshots + restauração
#
# ESCREVE (e só isto), no dataset smartbetting-dados.futebol_taskF:
#   - as saídas dos modelos stg_futebol_fixtures (view), fact_fixtures e int_futebol_team_form_pit;
#   - as tabelas leva8_bak_* (backup do estado de antes), leva8_pit_* e leva8_fixtures_* (snapshots).
# NUNCA escreve no dataset 'futebol', no GCS, nem em taskf_teste2*, taskf_pit_por_celula*, *_ancora.
#
# O taskF é COMPARTILHADO com quem mede âncora/Teste 2: o script recusa rodar se houve escrita alheia
# na última hora, e o trap RESTAURA fact_fixtures e int_futebol_team_form_pit (bq cp, preserva partição e
# cluster) e recria a view com a definição original MESMO se um build falhar. Um rebuild default NÃO
# restaura: ele refrescaria o taskF para hoje.
#
# Pré-requisitos: gcloud autenticado (login e application-default), bq e dbt no PATH (ou DBT_BIN),
# 01_baixa_fixtures.py, 02_monta_ndjson.py e 03_carrega_raw_fixtures.sh já rodados.
# Variáveis: TASKF_LEVA_OUT (padrão /tmp/taskf_leva), DBT_BIN (padrão dbt), DBT_PROFILES_DIR (padrão raiz
# do repo), RAW_ESPERADO (linhas esperadas em leva8_raw_fixtures; padrão 2990).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${TASKF_LEVA_OUT:-/tmp/taskf_leva}
DBT=${DBT_BIN:-dbt}
export DBT_PROFILES_DIR=${DBT_PROFILES_DIR:-$REPO}
RAW_ESPERADO=${RAW_ESPERADO:-2990}
P=smartbetting-dados
D=futebol_taskF
LOC=us-east1
MODO=${1:-checagens}
RESTAURAR=0
RESTAURADO=0
mkdir -p "$OUT"

bqq() { bq --location=$LOC query --use_legacy_sql=false --format=csv --quiet "$@"; }
agora() { date -u +%Y-%m-%dT%H:%M:%SZ; }

restaurar() {
  echo "[$(agora)] RESTAURANDO o taskF ao estado de antes dos builds"
  bq --location=$LOC cp -f $P:$D.leva8_bak_fact_fixtures $P:$D.fact_fixtures
  bq --location=$LOC cp -f $P:$D.leva8_bak_pit $P:$D.int_futebol_team_form_pit
  OUT="$OUT" python3 - <<'PY'
import json, os
out = os.environ["OUT"]
consulta = json.load(open(os.path.join(out, "stg_view_original.json")))["view"]["query"]
open(os.path.join(out, "stg_view_restaurar.sql"), "w").write(
    "CREATE OR REPLACE VIEW `smartbetting-dados.futebol_taskF.stg_futebol_fixtures` AS\n" + consulta + "\n")
PY
  bq --location=$LOC query --use_legacy_sql=false --quiet < "$OUT/stg_view_restaurar.sql"
  RESTAURADO=1
  echo "[$(agora)] RESTAURACAO_CONCLUIDA"
}

trap 'if [ "$RESTAURAR" = 1 ] && [ "$RESTAURADO" != 1 ]; then restaurar; fi' EXIT

echo "[$(agora)] INICIO modo=$MODO"

# ---- A. guarda de concorrência: nenhuma escrita alheia no taskF na última hora
cat > "$OUT/guarda.sql" <<'EOF'
SELECT COUNT(*) AS n_escritas_alheias_60min
FROM `smartbetting-dados`.`region-us-east1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 60 MINUTE)
  AND statement_type != 'SELECT'
  AND destination_table.dataset_id = 'futebol_taskF'
  AND NOT STARTS_WITH(destination_table.table_id, 'leva8_')
EOF
N=$(bqq < "$OUT/guarda.sql" | tail -1)
echo "A. escritas alheias no taskF nos últimos 60 min: $N"
if [ "$N" != "0" ]; then echo "ABORTANDO: outra sessão escreveu no taskF na última hora"; exit 2; fi

# ---- B. o taskF NÃO pode estar contaminado (uma execução anterior que morreu no meio) nem sem a carga
cat > "$OUT/confere.sql" <<'EOF'
SELECT
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.fact_fixtures`
     WHERE competition_id IN (128,239,281,262))                                       AS ff_com_ligas_novas,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`
     WHERE competition_id IN (128,239,281,262))                                       AS pit_com_ligas_novas,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.leva8_raw_fixtures`)       AS raw_leva
EOF
bqq < "$OUT/confere.sql" | tee "$OUT/confere.out"
LINHA=$(tail -1 "$OUT/confere.out")
FFN=$(echo "$LINHA" | cut -d, -f1); PTN=$(echo "$LINHA" | cut -d, -f2); RAW=$(echo "$LINHA" | cut -d, -f3)
if [ "$FFN" != "0" ] || [ "$PTN" != "0" ]; then
  echo "ABORTANDO: o taskF já tem linhas das 4 ligas (execução anterior interrompida?). Restaure antes de repetir."; exit 3
fi
if [ "$RAW" != "$RAW_ESPERADO" ]; then
  echo "ABORTANDO: leva8_raw_fixtures tem $RAW linhas, esperado $RAW_ESPERADO (rode 03_carrega_raw_fixtures.sh)"; exit 3
fi
TIPO=$(bq --location=$LOC show --format=prettyjson $P:$D.stg_futebol_fixtures | python3 -c 'import json,sys; print(json.load(sys.stdin)["type"])')
if [ "$TIPO" != "VIEW" ]; then echo "ABORTANDO: stg_futebol_fixtures no taskF não é VIEW (é $TIPO)"; exit 3; fi
echo "B. taskF sem as ligas novas, leva8_raw_fixtures=$RAW, stg é VIEW"

if [ "$MODO" != "completo" ]; then echo "[$(agora)] modo checagens: nada foi escrito. FIM"; exit 0; fi

# ---- C. backup do estado atual (antes de qualquer build) e definição da view
bq --location=$LOC show --format=prettyjson $P:$D.stg_futebol_fixtures > "$OUT/stg_view_original.json" || exit 4
bq --location=$LOC cp -f $P:$D.fact_fixtures $P:$D.leva8_bak_fact_fixtures || exit 4
bq --location=$LOC cp -f $P:$D.int_futebol_team_form_pit $P:$D.leva8_bak_pit || exit 4
cat > "$OUT/confere_bak.sql" <<'EOF'
SELECT
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.fact_fixtures`)             AS ff,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.leva8_bak_fact_fixtures`)   AS ff_bak,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`) AS pit,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.leva8_bak_pit`)             AS pit_bak
EOF
bqq < "$OUT/confere_bak.sql" | tee "$OUT/confere_bak.out"
BL=$(tail -1 "$OUT/confere_bak.out")
if [ "$(echo "$BL" | cut -d, -f1)" != "$(echo "$BL" | cut -d, -f2)" ] || [ "$(echo "$BL" | cut -d, -f3)" != "$(echo "$BL" | cut -d, -f4)" ]; then
  echo "ABORTANDO: backup não confere com o original"; exit 4
fi
echo "C. backups OK ($BL)"

# ---- D. builds (o trap garante a restauração a partir daqui)
RESTAURAR=1
build() {
  ROT=$1
  echo "[$(agora)] === BUILD $ROT ==="
  if [ "$ROT" = "antes" ]; then
    "$DBT" build --project-dir "$REPO/dbt_futebol" --target taskF --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit --full-refresh --exclude-resource-type test unit_test
  else
    "$DBT" build --project-dir "$REPO/dbt_futebol" --target taskF --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit --full-refresh --exclude-resource-type test unit_test --vars "{taskf_incluir_ligas_leva: \"$ROT\"}"
  fi
}
for ROT in 2025_2026 2026 antes; do
  if ! build $ROT > "$OUT/build_$ROT.log" 2>&1; then
    echo "ABORTANDO: build $ROT falhou (veja $OUT/build_$ROT.log); restaurando"; exit 5
  fi
  tail -3 "$OUT/build_$ROT.log"
  echo "CREATE OR REPLACE TABLE \`$P.$D.leva8_pit_$ROT\` AS SELECT * FROM \`$P.$D.int_futebol_team_form_pit\`" | bqq > /dev/null || exit 5
  echo "CREATE OR REPLACE TABLE \`$P.$D.leva8_fixtures_$ROT\` AS SELECT * FROM \`$P.$D.fact_fixtures\`" | bqq > /dev/null || exit 5
  echo "[$(agora)] snapshots de $ROT feitos"
done

# ---- E. restauração exata (o trap só roda se algo falhar; este é o caminho normal)
restaurar

# ---- F. verificação final
cat > "$OUT/final.sql" <<'EOF'
SELECT
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.fact_fixtures`)             AS ff,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`) AS pit,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.fact_fixtures`
     WHERE competition_id IN (128,239,281,262))                                        AS ff_com_ligas_novas,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`
     WHERE competition_id IN (128,239,281,262))                                        AS pit_com_ligas_novas,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.leva8_pit_antes`)            AS snap_antes,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.leva8_pit_2026`)             AS snap_2026,
  (SELECT COUNT(*) FROM `smartbetting-dados.futebol_taskF.leva8_pit_2025_2026`)        AS snap_2025_2026
EOF
bqq < "$OUT/final.sql" | tee "$OUT/final.out"
bq --location=$LOC show --format=prettyjson $P:$D.fact_fixtures | grep -E '"field": "date_utc"|"type": "DAY"|"competition"|"season"|"home_team_id"' | head -6
echo "[$(agora)] FIM_COMPLETO"
