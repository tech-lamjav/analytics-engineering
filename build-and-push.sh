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
IMAGE_TAG=latest

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

# Construir o nome completo da imagem
FULL_IMAGE_NAME="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

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
if ! git -C "$SCRIPT_DIR" diff --quiet -- $("$SCRIPT_DIR/scripts/procedencia.sh" "$PROJECT_NAME" --paths) 2>/dev/null; then
    echo "⚠️  AVISO: ha alteracao nao commitada nas paths comportamentais de ${PROJECT_NAME}."
    echo "    O carimbo vai refletir o DISCO, entao o detector de deriva vai ficar VERMELHO"
    echo "    ate esse codigo estar no master. Isso e o comportamento correto, nao um erro."
fi

echo "=========================================="
echo "Build e Push da Imagem Docker"
echo "=========================================="
echo "Projeto dbt: ${PROJECT_NAME}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Projeto GCP: ${GCP_PROJECT_ID}"
echo "Região: ${GCP_REGION}"
echo "Repositório: ${ARTIFACT_REGISTRY_REPO}"
echo "Imagem: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Nome completo: ${FULL_IMAGE_NAME}"
echo "Cloud Run Job: ${JOB_NAME}"
echo "Carimbo (procedência): ${PROCEDENCIA_HASH}"
echo "Commit (leitura humana): ${PROCEDENCIA_SHA}"
echo "=========================================="
echo ""

# Autenticar Docker no Artifact Registry via access token
echo "Configurando autenticação Docker..."
gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://${GCP_REGION}-docker.pkg.dev

# Build da imagem para linux/amd64 (requerido pelo Cloud Run)
echo ""
echo "Fazendo build da imagem para linux/amd64..."
docker build --platform linux/amd64 -f ${DOCKERFILE} -t ${FULL_IMAGE_NAME} .

# Push para Artifact Registry
echo ""
echo "Fazendo push para Artifact Registry..."
docker push ${FULL_IMAGE_NAME}

# Deploy: repin do digest no job + gravação do carimbo, NO MESMO COMANDO.
# O job resolve `:latest` para um digest no momento do update e as execuções herdam esse
# digest — sem este passo, o push acima não muda absolutamente nada em produção.
#
# `--update-env-vars` e não `--set-env-vars`: o segundo substitui o mapa inteiro de env vars,
# então qualquer variável que alguém venha a acrescentar ao job seria apagada em silêncio no
# próximo build.
echo ""
echo "Atualizando Cloud Run Job ${JOB_NAME} (digest + carimbo)..."
gcloud run jobs update "$JOB_NAME" \
    --region="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --image="$FULL_IMAGE_NAME" \
    --update-env-vars="PROCEDENCIA_HASH=${PROCEDENCIA_HASH},PROCEDENCIA_SHA=${PROCEDENCIA_SHA}"

echo ""
echo "=========================================="
echo "✅ Build, push e deploy concluídos com sucesso!"
echo "=========================================="
echo "Imagem disponível em: ${FULL_IMAGE_NAME}"
echo "Job ${JOB_NAME} carimbado com: ${PROCEDENCIA_HASH}"
echo ""
echo "Digest efetivamente fixado no job:"
gcloud run jobs describe "$JOB_NAME" \
    --region="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --format="value(spec.template.spec.template.spec.containers[0].image)"
echo ""
echo "Para executar localmente:"
echo "  docker run ${FULL_IMAGE_NAME}"
echo ""
