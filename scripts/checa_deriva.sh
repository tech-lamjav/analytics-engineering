#!/bin/bash
# Detector de DERIVA: o que roda em produção é o que está no master?
#
# Compara o carimbo de procedência gravado em cada Cloud Run Job com o hash recalculado da
# árvore local. Divergência = a imagem em produção não corresponde ao código.
#
# Uso:
#   scripts/checa_deriva.sh            # checa todos os alvos
#   scripts/checa_deriva.sh dbt_nba    # checa um alvo
#
# POR QUE ESTE DETECTOR NÃO VIVE NA IMAGEM:
# a fase de guardas (`dbt test --select tag:guarda`) roda da MESMA imagem que os modelos que
# ela protege. Imagem velha causa o bug E apaga o detector — a guarda é estruturalmente cega
# para "a imagem não foi rebuildada". Em 07/08/2026 a fase de guardas do futebol rodou com
# TOTAL=6 em vez de 13 porque as 7 tags novas estavam no master e não na imagem. Este script
# roda FORA da imagem, no GitHub Actions, e é o único que enxerga essa classe.
#
# Ver docs/adr/0001-carimbo-de-procedencia-da-imagem-dbt.md

set -uo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-smartbetting-dados}"
GCP_REGION="${GCP_REGION:-us-east1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Tabela declarativa de alvos. Acrescentar um alvo é acrescentar um nome aqui — desde que
# `scripts/procedencia.sh` conheça as paths dele.
#
# ⚠️ ISTO VALE SÓ PARA ALVOS DESTE REPO. Os serviços Cloud Run do `data-engineering` NÃO
# entram por esta porta, ao contrário do que este comentário afirmou até 24/08/2026: o
# `procedencia.sh` hasheia paths relativas ao `git rev-parse --show-toplevel`, que aqui é
# sempre o analytics-engineering. O desenho é genérico quanto ao ALVO, não quanto ao
# REPOSITÓRIO. Eles têm detector irmão e dono próprio lá — ver
# data-engineering/docs/adr/0001-carimbo-de-procedencia-dos-servicos-cloud-run.md
# (o bullet corrigido em Consequências do ADR 0001 conta por quê).
if [ $# -gt 0 ]; then
    ALVOS=("$@")
else
    ALVOS=(dbt_futebol dbt_nba)
fi

derivas=0
erros=0

for PROJECT_NAME in "${ALVOS[@]}"; do
    JOB_NAME=$(echo "$PROJECT_NAME" | tr '_' '-')
    echo "── ${PROJECT_NAME} (job ${JOB_NAME})"

    ESPERADO=$("$SCRIPT_DIR/procedencia.sh" "$PROJECT_NAME") || {
        echo "   ERRO: nao consegui calcular o hash local de ${PROJECT_NAME}"
        erros=$((erros + 1))
        continue
    }

    # Lê o carimbo direto do job. Só precisa de roles/run.viewer — nunca toca o Artifact
    # Registry. O carimbo vive no job (e não como LABEL da imagem) porque o que apodrece é
    # o DIGEST FIXADO NO JOB, não a tag da imagem: é essa a coisa a interrogar.
    # `--format=json` inteiro, e não `--format="json(caminho)"`: quando o caminho não
    # resolve, o segundo devolve o literal `null` em vez do esqueleto aninhado, e o parser
    # quebra. Um detector que acusa deriva porque o próprio parser quebrou é um detector
    # falso — por isso "erro de leitura" e "carimbo ausente" são casos separados abaixo.
    JOB_JSON=$(gcloud run jobs describe "$JOB_NAME" \
        --region="$GCP_REGION" \
        --project="$GCP_PROJECT_ID" \
        --format=json 2>&1) || {
        echo "   ERRO: nao consegui ler o job ${JOB_NAME}:"
        echo "$JOB_JSON" | sed 's/^/     /'
        erros=$((erros + 1))
        continue
    }

    ENCONTRADO=$(echo "$JOB_JSON" | python3 -c '
import json, sys

doc = json.load(sys.stdin)          # erro de parse aborta com stacktrace: e erro, nao deriva
spec = doc["spec"]["template"]["spec"]["template"]["spec"]
# `env` some do JSON quando o job nao tem nenhuma variavel — que e o estado inicial dos
# dois jobs. Ausencia da chave e ausencia do carimbo, tratada como deriva pelo chamador.
for var in spec["containers"][0].get("env") or []:
    if var.get("name") == "PROCEDENCIA_HASH":
        print(var.get("value") or "")
        break
') || {
        echo "   ERRO: nao consegui interpretar a resposta do job ${JOB_NAME}"
        erros=$((erros + 1))
        continue
    }

    if [ -z "$ENCONTRADO" ]; then
        # FAIL-CLOSED. Um detector que fica quieto quando não sabe é indistinguível de um
        # detector desligado — que é exatamente o defeito que este script existe para
        # corrigir. Carimbo ausente é deriva até prova em contrário.
        echo "   ❌ DERIVA: o job nao tem carimbo (PROCEDENCIA_HASH ausente)."
        echo "      Rode: ./build-and-push.sh ${PROJECT_NAME}"
        derivas=$((derivas + 1))
    elif [ "$ENCONTRADO" != "$ESPERADO" ]; then
        echo "   ❌ DERIVA: a imagem em producao nao corresponde ao codigo."
        echo "      no job:  ${ENCONTRADO}"
        echo "      no repo: ${ESPERADO}"
        echo "      Rode: ./build-and-push.sh ${PROJECT_NAME}"
        derivas=$((derivas + 1))
    else
        echo "   ✅ em dia (${ESPERADO})"
    fi
done

echo
if [ "$derivas" -gt 0 ] || [ "$erros" -gt 0 ]; then
    echo "RESULTADO: ${derivas} alvo(s) em deriva, ${erros} erro(s) de leitura."
    echo
    echo "Deriva significa que producao esta rodando codigo diferente do master — e que a"
    echo "fase de guardas dbt NAO vai acusar isso, porque ela roda da mesma imagem derivada."
    exit 1
fi

echo "RESULTADO: todos os alvos em dia."
