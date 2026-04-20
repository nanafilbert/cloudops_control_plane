# 🚀 cloudops_control_plane

A production-grade Kubernetes Control Plane and microservices ecosystem built on AWS EKS.  
This project demonstrates a **Day 2 operations mindset** – Zero-Trust Security, Cost Optimization (FinOps), and Operational Excellence.

## 📌 Overview

Not just a container deployment – this repo shows how to **design, operate, and govern** a cloud-native system in a realistic environment:

- Secure identity (no static credentials – OIDC + IRSA)
- Cost-aware infrastructure (kept under $30/month)
- Observability (Prometheus, Grafana, Loki)
- Clean, documented engineering decisions (ADRs)

## 🏗️ Architecture
[User] → Route53 → ALB → Ingress-Nginx → K8s Service (ClusterIP) → Game Pods → RDS (PostgreSQL)

text

VPC with 2 AZs, public/private subnets, NAT Gateway, EKS managed nodes (t3.medium).

## 🔧 Tech Stack

| Layer       | Tools                                                                 |
|-------------|-----------------------------------------------------------------------|
| Compute     | EKS (Kubernetes 1.28)                                                |
| Database    | RDS (PostgreSQL) + Secrets Manager                                    |
| Secrets     | External Secrets Operator + Sealed Secrets                            |
| CI/CD       | GitHub Actions (OIDC assume role)                                     |
| Governance  | Cloud Custodian + Python cost reporting                               |
| Observability | Prometheus, Grafana, Loki (scrape every 10s, custom dashboards)    |

## 🔐 Key Engineering Pillars

### 1. Zero-Trust Identity (OIDC + IRSA)
- No IAM access keys in GitHub – OIDC federation.
- Pods use IRSA to read Secrets Manager.
- Network Policies enforce default-deny, explicit ingress/egress.

### 2. Automated FinOps
- AWS Budget alert at $30/month.
- Cloud Custodian policies stop idle EC2, remove unused EBS.
- Daily cost report via Python/Boto3 (fails workflow if exceeded).

### 3. Decoupled Secrets Management
- External Secrets Operator syncs from AWS Secrets Manager.
- Sealed Secrets for encrypted Git storage (API keys, tokens).

### 4. Lean Observability
- Prometheus scrapes metrics every 10 seconds.
- Grafana dashboards (Golden Signals, WebSocket metrics, DB stats).
- Loki for log aggregation.
- PrometheusRules for critical alerts (high error rate, service down, high latency, DB pool exhaustion).

## 📂 Project Structure (Separation of Concerns)

- `bootstrap/` – S3 backend + DynamoDB lock + GitHub OIDC role (one-time)
- `terraform/modules/` – reusable VPC, EKS, RDS, IRSA, security
- `terraform/env/dev/` – root config calling modules (dev environment)
- `services/game-service/` – your Django game (submodule)
- `helm/` – Helm charts for auth, user, game services
- `kubernetes/` – Kustomize base + overlays (namespaces, network policies, HPA)
- `configs/` – environment-specific Helm values
- `finops/` – cost automation, Infracost config, monthly reports
- `governance/` – AWS budgets, Checkov config, Custodian policies
- `scripts/` – helper scripts for deployment, monitoring, secrets
- `docs/` – ADRs, runbooks, onboarding, architecture
- `.github/workflows/` – 6 single‑purpose CI/CD workflows

## 🚀 Quick Start

### Prerequisites
- AWS CLI, Terraform 1.3+, kubectl, Helm, Python 3.10+, `boto3`
- AWS account with admin privileges (for bootstrap)

### One-time bootstrap (per AWS account)
```bash
cd bootstrap/backend && terraform apply -var="account_id=123456789012"
cd ../iam && terraform apply -var="github_repo=your-org/cloudops_control_plane"
Add GH_OIDC_ROLE_ARN secret to GitHub repository.

Deploy environment
bash
cd terraform/env/dev
terraform init
terraform apply -auto-approve
./scripts/deploy.sh
Access Grafana
bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# URL: http://localhost:3000, user: admin, password: prom-operator
📊 CI/CD Pipeline
Workflow	Trigger	Purpose
01-terraform-plan.yml	PR on Terraform files	Plan + Checkov + Infracost + comment on PR
02-terraform-apply.yml	Push to main (after plan)	Apply saved plan
03-docker-build.yml	After apply	Build & push images for all services
04-k8s-deploy.yml	After docker build	Kustomize + Helm + monitoring stack
05-finops-reporter.yml	Daily & on push	Cost report + budget alert
06-destroy.yml	Manual	Full environment teardown
📚 Documentation
Architecture

Decision Records (ADRs)

Runbooks

Onboarding Guide

⚠️ Limitations
Single replica setup (cost optimization) – not for production high traffic.

Designed to demonstrate architecture, not scale limits.

🧠 What This Project Proves
Infrastructure as Code best practices (modular Terraform)

Secure CI/CD pipelines (OIDC, no static secrets)

Cost-aware cloud architecture (FinOps)

Operational readiness (Day 2 thinking)

Observability + alerting (SRE practices)

📬 Final Note
Every decision balances cost, security, and operational complexity – real engineering trade-offs, not idealized architectures.