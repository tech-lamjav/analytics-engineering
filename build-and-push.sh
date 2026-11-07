#!/bin/bash

# Script para build, push e DEPLOY da imagem Docker do projeto dbt.
# Uso:
#   ./build-and-push.sh              # default: dbt_nba (compatibilidade)
#   ./build-and-push.sh dbt_futebol  # build do projeto futebol
#
# ⚠️ Este script agora TAMBÉM atualiza o Cloud Run Job (`gcloud run jobs update`). Antes ele
# parava no push, e o `jobs update` era um segundo comando manual — foi exatamente esse
# segundo passo esquecido que deixou o de-vig 2 dias fora de produção (futebol, 05-07/08/2026)
# e o dbt_nba 6 semanas atrás do master. O job fixa o DIGEST, não a tag: empurrar `:latest`
# sem `jobs update` não muda nada em produção. Os dois passos são um só agora, de propósito.
#
# O mesmo comando grava o CARIMBO DE PROCEDÊNCIA (`scripts/procedencia.sh`) como env var do
# job, para que build, digest e carimbo não possam divergir. Ver docs/adr/0001.
#
# TAGS E ARTIFACT REGISTRY (cleanup policy, ver data-engineering/infra/README.md):
#   git-<sha>   a imagem deste build (rastreável até o commit; `-sujo` se o disco divergia).
#               É a ÚNICA tag empurrada antes do `jobs update`.
#   live        o digest que o JOB roda. Só é movida DEPOIS do `jobs update` dar certo:
#               empurrada junto com o build, ela marcaria um digest que o job talvez nunca
#               rode (o mesmo erro do `latest` do `deploy --source`), e a cleanup policy
#               poderia apagar o digest vivo.
#   live-prev   ROLANTE: o digest que tinha `live` até este build, o alvo de rollback (N-1).
#               Movida antes da `live`, para o digest antigo não ficar um instante sem tag.
#               Um nome só, que se move: nunca vira Keep eterno.
#   latest      conveniência humana (`docker run`). Também só depois do `jobs update`: a
#               policy dos repos dbt mantém `latest`, então um `latest` num build que
#               falhou no update seria mais um Keep num digest que ninguém roda.
# O job é atualizado com `--image ...@sha256:<digest>`, não com a tag: o que roda fica
# explícito no spec do job, e mover `latest` depois não muda nada por engano.
# `--provenance=false --sbom=false`: sem isso o buildx empurra um índice com manifests de
# attestation, e cada build vira várias versões no registry em vez de uma.

set -e

# Argumento: nome do projeto dbt (default dbt_nba). Define imagem, repo e Dockerfile.
PROJECT_NAME="${1:-dbt_nba}"

# Variáveis de ambiente (pode ser sobrescrito)
GCP_PROJECT_ID=smartbetting-dados
GCP_REGION=us-east1

# Convenção: nome do repo/imagem deriva do PROJECT_NAME (substitui _ por -)
# dbt_nba     -> repo dbt-nba-repo,     imagem dbt-nba,     Dockerfile
# dbt_futebol -> repo dbt-futebol-repo, imagem dbt-futebol, Dockerfile.futebol
NORMALIZED_NAME=$(echo "$PROJECT_NAME" | tr '_' '-')
ARTIFACT_REGISTRY_REPO="${NORMALIZED_NAME}-repo"
IMAGE_NAME="$NORMALIZED_NAME"

if [ "$PROJECT_NAME" = "dbt_nba" ]; then
    DOCKERFILE="Dockerfile"
else
    # dbt_futebol -> Dockerfile.futebol; padrão: Dockerfile.<sufixo após dbt_>
    SUFFIX="${PROJECT_NAME#dbt_}"
    DOCKERFILE="Dockerfile.${SUFFIX}"
fi

if [ ! -f "$DOCKERFILE" ]; then
    echo "ERROR: Dockerfile não encontrado: $DOCKERFILE" >&2
    exit 1
fi

# Pacote no Artifact Registry (sem tag); as tags vêm abaixo, depois do carimbo.
PACOTE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}/${IMAGE_NAME}"

# Nome do Cloud Run Job: mesma convenção da imagem (dbt_futebol -> dbt-futebol).
JOB_NAME="$NORMALIZED_NAME"

# Carimbo de procedência: hash do conteúdo EM DISCO das paths comportamentais — calculado
# ANTES do build, da mesma árvore que o `docker build` vai copiar. O SHA do git vai junto só
# para leitura humana (não é o que o detector compara).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCEDENCIA_HASH="$("$SCRIPT_DIR/scripts/procedencia.sh" "$PROJECT_NAME")"
PROCEDENCIA_SHA="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "sem-git")"

# Aviso — não bloqueio. Buildar de branch/worktree com alteração não commitada é legítimo
# (hotfix, depuração) e o repo trabalha assim. O carimbo simplesmente vai refletir o disco,
# então o detector vai acusar deriva até o código ser mergeado — que é a verdade, não um bug.
SUJO=""
if ! git -C "$SCRIPT_DIR" diff --quiet -- $("$SCRIPT_DIR/scripts/procedencia.sh" "$PROJECT_NAME" --paths) 2>/dev/null; then
    SUJO="-sujo"
    echo "⚠️  AVISO: ha alteracao nao commitada nas paths comportamentais de ${PROJECT_NAME}."
    echo "    O carimbo vai refletir o DISCO, entao o detector de deriva vai ficar VERMELHO"
    echo "    ate esse codigo estar no master. Isso e o comportamento correto, nao um erro."
fi

TAG_GIT="git-${PROCEDENCIA_SHA}${SUJO}"
IMAGEM_GIT="${PACOTE}:${TAG_GIT}"

echo "=========================================="
echo "Build e Push da Imagem Docker"
echo "=========================================="
echo "Projeto dbt: ${PROJECT_NAME}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Projeto GCP: ${GCP_PROJECT_ID}"
echo "Região: ${GCP_REGION}"
echo "Repositório: ${ARTIFACT_REGISTRY_REPO}"
echo "Imagem: ${IMAGE_NAME} (tags ${TAG_GIT} e latest; live depois do jobs update)"
echo "Pacote: ${PACOTE}"
echo "Cloud Run Job: ${JOB_NAME}"
echo "Carimbo (procedência): ${PROCEDENCIA_HASH}"
echo "Commit (leitura humana): ${PROCEDENCIA_SHA}"
echo "=========================================="
echo ""

# Autenticar Docker no Artifact Registry via access token
echo "Configurando autenticação Docker..."
gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://${GCP_REGION}-docker.pkg.dev

# Build da imagem para linux/amd64 (requerido pelo Cloud Run). Uma versão por build no
# registry: sem attestation de provenance/SBOM (ver o cabeçalho).
echo ""
echo "Fazendo build da imagem para linux/amd64..."
docker build --platform linux/amd64 --provenance=false --sbom=false \
    -f "${DOCKERFILE}" -t "${IMAGEM_GIT}" .

# Push para Artifact Registry: só `git-<sha>`. `live`, `live-prev` e `latest` só depois do
# `jobs update` (ver o cabeçalho).
echo ""
echo "Fazendo push para Artifact Registry..."
docker push "${IMAGEM_GIT}"

# Digest lido do REGISTRY (a fonte da verdade do que foi empurrado), não do docker local.
# Vazio ou fora do formato = aborta ANTES do jobs update: o job não pode ser re-apontado
# para um digest que ninguém confirmou.
DIGEST=$(gcloud artifacts docker images describe "${IMAGEM_GIT}" \
    --project="$GCP_PROJECT_ID" \
    --format='value(image_summary.digest)')
if ! [[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "ERROR: digest de ${IMAGEM_GIT} ilegivel no Artifact Registry: '${DIGEST}'" >&2
    echo "       O job ${JOB_NAME} NAO foi atualizado." >&2
    exit 1
fi
IMAGEM_DIGEST="${PACOTE}@${DIGEST}"

# Digest que tem `live` HOJE, lido ANTES do `jobs update`: se a leitura falhar, nada em
# produção mudou ainda. Vazio = pacote sem `live` (primeiro build depois da mudança).
if ! TAGS_JSON=$(gcloud artifacts docker tags list "$PACOTE" --project="$GCP_PROJECT_ID" --format=json); then
    echo "ERROR: nao consegui ler as tags de ${PACOTE}. O job ${JOB_NAME} NAO foi atualizado." >&2
    exit 1
fi
LIVE_ATUAL=$(printf '%s' "$TAGS_JSON" | python3 -c '
import json, sys
for t in json.load(sys.stdin) or []:
    if (t.get("tag") or "").rsplit("/", 1)[-1] == "live":
        print((t.get("version") or "").rsplit("/", 1)[-1])
')

# Deploy: repin do digest no job + gravação do carimbo, NO MESMO COMANDO.
# O job roda exatamente o digest passado aqui; sem este passo, o push acima não muda
# absolutamente nada em produção.
#
# `--update-env-vars` e não `--set-env-vars`: o segundo substitui o mapa inteiro de env vars,
# então qualquer variável que alguém venha a acrescentar ao job seria apagada em silêncio no
# próximo build.
echo ""
echo "Atualizando Cloud Run Job ${JOB_NAME} (digest + carimbo)..."
gcloud run jobs update "$JOB_NAME" \
    --region="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --image="$IMAGEM_DIGEST" \
    --update-env-vars="PROCEDENCIA_HASH=${PROCEDENCIA_HASH},PROCEDENCIA_SHA=${PROCEDENCIA_SHA}"

# Só agora as tags: o job já aponta para este digest. Daqui para baixo o job JÁ roda a imagem
# nova; uma falha de tag não desfaz isso, mas deixa o digest vivo sem a proteção da cleanup
# policy. Por isso cada falha diz o comando que completa o serviço.
remedio_tags() {
    echo "" >&2
    echo "ERROR: o job ${JOB_NAME} JA roda ${IMAGEM_DIGEST}, mas a tag $1 nao foi aplicada." >&2
    echo "       Sem ela a cleanup policy pode apagar a imagem do job. Complete a mao:" >&2
    if [ -n "$LIVE_ATUAL" ] && [ "$LIVE_ATUAL" != "$DIGEST" ]; then
        echo "  gcloud artifacts docker tags add ${PACOTE}@${LIVE_ATUAL} ${PACOTE}:live-prev" >&2
    fi
    echo "  gcloud artifacts docker tags add ${IMAGEM_DIGEST} ${PACOTE}:live" >&2
    echo "  gcloud artifacts docker tags add ${IMAGEM_DIGEST} ${PACOTE}:latest" >&2
    exit 1
}

echo ""
if [ -n "$LIVE_ATUAL" ] && [ "$LIVE_ATUAL" != "$DIGEST" ]; then
    echo "Movendo a tag live-prev para ${LIVE_ATUAL} (a live anterior)..."
    gcloud artifacts docker tags add "${PACOTE}@${LIVE_ATUAL}" "${PACOTE}:live-prev" --quiet \
        || remedio_tags live-prev
fi
echo "Movendo as tags live e latest para ${DIGEST}..."
gcloud artifacts docker tags add "$IMAGEM_DIGEST" "${PACOTE}:live" --quiet || remedio_tags live
gcloud artifacts docker tags add "$IMAGEM_DIGEST" "${PACOTE}:latest" --quiet || remedio_tags latest

echo ""
echo "=========================================="
echo "✅ Build, push e deploy concluídos com sucesso!"
echo "=========================================="
echo "Job ${JOB_NAME} roda: ${IMAGEM_DIGEST}"
echo "Tags: ${TAG_GIT}, live, latest${LIVE_ATUAL:+ (live-prev: ${LIVE_ATUAL})}"
echo "Job ${JOB_NAME} carimbado com: ${PROCEDENCIA_HASH}"
echo ""
echo "Carimbo agora gravado no job (o que o detector le):"
gcloud run jobs describe "$JOB_NAME" \
    --region="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --format="value(spec.template.spec.template.spec.containers[0].env)"
echo ""
echo "Para executar localmente:"
echo "  docker run ${IMAGEM_DIGEST}"
echo ""
