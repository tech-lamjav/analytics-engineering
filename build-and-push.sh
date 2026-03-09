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

# Autenticar Docker no Artifact Registry via access token
echo "Configurando autenticação Docker..."
gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://${GCP_REGION}-docker.pkg.dev

# Build da imagem para linux/amd64 (requerido pelo Cloud Run)
echo ""
echo "Fazendo build da imagem para linux/amd64..."
docker build --platform linux/amd64 -t ${FULL_IMAGE_NAME} .

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
