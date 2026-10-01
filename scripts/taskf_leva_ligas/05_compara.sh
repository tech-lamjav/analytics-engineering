#!/bin/bash
# Roda a análise dbt_futebol/analyses/taskf_leva_ligas_efeito_retroativo.sql contra os snapshots
# leva8_pit_antes, leva8_pit_2026 e leva8_pit_2025_2026 e grava a matriz em CSV. SÓ LEITURA.
#
# A análise é um arquivo de analyses/: o cabeçalho é um bloco de comentário Jinja {# ... #} e o resto é
# SQL puro com nomes literais de tabela. Este script só tira o bloco Jinja e manda para o bq.
#
# uso: bash scripts/taskf_leva_ligas/05_compara.sh [arquivo_csv_saida]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
BASE=${TASKF_LEVA_OUT:-/tmp/taskf_leva}
SAIDA=${1:-$BASE/matriz.csv}
mkdir -p "$BASE"

ANALISE="$REPO/dbt_futebol/analyses/taskf_leva_ligas_efeito_retroativo.sql"
SQL="$BASE/matriz.sql"
ANALISE="$ANALISE" SQL="$SQL" python3 - <<'PY'
import os, re
texto = open(os.environ["ANALISE"]).read()
sem_jinja = re.sub(r"\{#.*?#\}", "", texto, count=1, flags=re.S)
assert "{{" not in sem_jinja and "{%" not in sem_jinja, "sobrou Jinja na análise"
open(os.environ["SQL"], "w").write(sem_jinja)
PY
bq --location=us-east1 query --use_legacy_sql=false --format=csv --max_rows=1000 --quiet < "$SQL" > "$SAIDA" || exit 2
echo "matriz em $SAIDA ($(($(wc -l < "$SAIDA") - 1)) linhas); o controle (controle_lib_sud e controle_outras) tem de dar delta exato 0"
