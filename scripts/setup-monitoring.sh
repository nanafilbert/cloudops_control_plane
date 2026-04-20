#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}📊 Installing Prometheus stack...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (Prometheus + Grafana)
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    -f kubernetes/monitoring/prometheus-values.yaml

# Install Loki for log aggregation
helm upgrade --install loki grafana/loki-stack \
    --namespace logging \
    --create-namespace \
    -f kubernetes/monitoring/loki-values.yaml

# Apply custom dashboard and alerts
kubectl apply -f kubernetes/monitoring/grafana-dashboard-game.yaml
kubectl apply -f kubernetes/monitoring/prometheus-alerts.yaml

echo -e "${GREEN}✅ Monitoring stack installed${NC}"
echo -e "${GREEN}🔑 Grafana admin password: prom-operator${NC}"
echo -e "${GREEN}➡️  Access Grafana: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring${NC}"