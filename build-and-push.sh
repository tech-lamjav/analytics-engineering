#!/bin/bash

# Script para build e push da imagem Docker para Artifact Registry
# Uso: ./build-and-push.sh

set -e

# Variáveis de ambiente (pode ser sobrescrito)
GCP_PROJECT_ID=smartbetting-dados
GCP_REGION=us-east1
ARTIFACT_REGISTRY_REPO=dbt-nba-repo
IMAGE_NAME=dbt-nba
IMAGE_TAG=latest

# Construir o nome completo da imagem
FULL_IMAGE_NAME="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "Build e Push da Imagem Docker"
echo "=========================================="
echo "Projeto GCP: ${GCP_PROJECT_ID}"
echo "Região: ${GCP_REGION}"
echo "Repositório: ${ARTIFACT_REGISTRY_REPO}"
echo "Imagem: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Nome completo: ${FULL_IMAGE_NAME}"
echo "=========================================="
echo ""

# Configurar Docker para usar gcloud como credential helper
echo "Configurando autenticação Docker..."
gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev --quiet

# Criar builder buildx se não existir (necessário para multiplataforma)
echo ""
echo "Configurando Docker buildx..."
docker buildx create --use --name multiarch-builder 2>/dev/null || docker buildx use multiarch-builder

# Build da imagem para linux/amd64 (requerido pelo Cloud Run) e push direto
echo ""
echo "Fazendo build da imagem para linux/amd64 e push para Artifact Registry..."
docker buildx build --platform linux/amd64 -t ${FULL_IMAGE_NAME} --push .

echo ""
echo "=========================================="
echo "✅ Build e push concluídos com sucesso!"
echo "=========================================="
echo "Imagem disponível em: ${FULL_IMAGE_NAME}"
echo ""
echo "Para executar localmente:"
echo "  docker run ${FULL_IMAGE_NAME}"
echo ""
