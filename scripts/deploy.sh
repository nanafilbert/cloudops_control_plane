#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting deployment of cloudops_control_plane...${NC}"

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}❌ Terraform is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}❌ kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}❌ Helm is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ AWS CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }

# Set variables
ENV=${1:-dev}
TF_DIR="terraform/env/${ENV}"
KUBE_CLUSTER="cloudops-${ENV}"

echo -e "${GREEN}📦 Deploying environment: ${ENV}${NC}"

# Terraform apply
echo -e "${GREEN}🏗️  Applying Terraform...${NC}"
cd "${TF_DIR}"
terraform init
terraform apply -auto-approve
cd -

# Update kubeconfig
echo -e "${GREEN}🔑 Updating kubeconfig for EKS cluster...${NC}"
aws eks update-kubeconfig --name "${KUBE_CLUSTER}" --region us-east-1

# Install monitoring (if not already installed)
echo -e "${GREEN}📊 Setting up monitoring stack...${NC}"
./scripts/setup-monitoring.sh

# Install External Secrets operator (if not already installed)
echo -e "${GREEN}🔐 Setting up External Secrets...${NC}"
./scripts/setup-secrets.sh

# Apply Kustomize base + overlay
echo -e "${GREEN}☸️  Applying Kubernetes resources...${NC}"
kubectl apply -k "kubernetes/overlays/${ENV}"

# Deploy Helm charts
echo -e "${GREEN}🚢 Deploying Helm charts...${NC}"
for service in auth-service user-service game-service; do
    helm upgrade --install "${service}" "./helm/${service}" \
        --namespace "game-${ENV}" \
        -f "configs/${ENV}/values-${service}.yaml" \
        --wait
done

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo -e "${GREEN}🌐 Access game at: https://game.${ENV}.yourdomain.com${NC}"