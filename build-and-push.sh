#!/bin/bash

# Script para build e push da imagem Docker para Artifact Registry
# Uso:
#   ./build-and-push.sh              # default: dbt_nba (compatibilidade)
#   ./build-and-push.sh dbt_futebol  # build do projeto futebol

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

echo ""
echo "=========================================="
echo "✅ Build e push concluídos com sucesso!"
echo "=========================================="
echo "Imagem disponível em: ${FULL_IMAGE_NAME}"
echo ""
echo "Para executar localmente:"
echo "  docker run ${FULL_IMAGE_NAME}"
echo ""
