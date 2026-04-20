#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}🔐 Installing External Secrets Operator...${NC}"

# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install or upgrade the operator
helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set installCRDs=true \
    --wait

echo -e "${GREEN}⏳ Waiting for External Secrets operator to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets --timeout=60s

echo -e "${GREEN}🔐 Applying SecretStore and ExternalSecret...${NC}"
kubectl apply -f kubernetes/secrets/secretstore.yaml
kubectl apply -f kubernetes/secrets/externalsecret.yaml
kubectl apply -f kubernetes/secrets/externalsecret-redis.yaml

echo -e "${GREEN}✅ Secrets configured. The game-db-credentials secret will be synced from AWS Secrets Manager.${NC}"