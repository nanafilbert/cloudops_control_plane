# cloudops_control_plane

> A production-grade Kubernetes control plane built on AWS EKS — evolving a real Django WebSocket trivia game from a two-server EC2 architecture into a fully automated, zero-credential, cloud-native platform under $30/month.

[![Terraform](https://img.shields.io/badge/IaC-Terraform_1.3+-7B42BC?logo=terraform)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36-326CE5?logo=kubernetes)](https://kubernetes.io)
[![AWS EKS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazonaws)](https://aws.amazon.com/eks)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions_OIDC-2088FF?logo=githubactions)](https://github.com/features/actions)
[![Security](https://img.shields.io/badge/Security-Trivy_+_Checkov-red?logo=aqua)](https://trivy.dev)
[![Live](https://img.shields.io/badge/Live-game.therealblessing.com-00C853?logo=googlechrome)](https://game.therealblessing.com)
[![Cost](https://img.shields.io/badge/Monthly_Cost-<$30-orange)](https://aws.amazon.com/pricing)

---

## What This Is

**DevOps Trivia** is a real-time browser quiz game where players pick a topic room, choose a difficulty, and answer 10 questions against a live leaderboard. Every completed game instantly updates the global leaderboard visible to all connected players simultaneously via WebSockets.

This repository is **not** the game itself — that lives at [github.com/nanafilbert/devops-trivia](https://github.com/nanafilbert/devops-trivia) and is included here as a git submodule under `services/game-service/`. This repository is the **platform** that runs it: infrastructure, automation, security, observability, and operational tooling.

**The full story is an evolution.** The game previously ran on two EC2 instances in private subnets, connected by a WireGuard VPN tunnel, behind an ALB. It worked — but recovery was manual, scaling was impossible, and every operational task required SSH. This repository is the next chapter: the same application, now on Kubernetes, fully automated, with zero static credentials anywhere in the system.

**Live:** [https://game.therealblessing.com](https://game.therealblessing.com)
**Previous EC2 architecture:** [github.com/nanafilbert/eks-to-ec2](https://github.com/nanafilbert/eks-to-ec2)

---

## The Game

Ten deep technical topic rooms, 60 questions each (30 easy, 30 hard):

| Room | Topics |
|---|---|
| Infrastructure & Cloud | VPCs, auto scaling, IaC, disaster recovery |
| Security & Defense | Encryption, zero trust, OWASP, CVEs |
| Networking & Protocols | TCP/IP, BGP, DNS, routing, VPNs |
| Containers & Orchestration | Docker, Kubernetes, CNI, operators |
| CI/CD & Automation | GitHub Actions, OIDC, GitOps, DORA metrics |
| Observability & Reliability | SLOs, OpenTelemetry, Prometheus, chaos engineering |
| Databases & Storage | MVCC, sharding, replication, WAL, indexing |
| Architecture & Design | Microservices, CQRS, event sourcing, CAP theorem |
| Linux & Systems | Kernel, processes, memory, namespaces, cgroups |
| APIs & Communication | REST, GraphQL, gRPC, WebSockets, message queues |

---

## Architecture

### Traffic Flow

```
Player's browser
      │
      │ HTTPS (game.therealblessing.com)
      ▼
Namecheap DNS → CNAME → cloudops-dev-nlb.elb.us-east-1.amazonaws.com
      │
      ▼
AWS Network Load Balancer (cloudops-dev-nlb)
      │  TLS terminated here via ACM wildcard cert (*.therealblessing.com)
      │  Port 443 only — port 80 deliberately removed
      ▼
ingress-nginx controller (plain HTTP from NLB)
      │  HSTS enforced, routes by Host header
      ▼
game-service Pod (Django + Daphne ASGI, port 8000)
      ├── HTTP → Django views (rooms, questions, game flow)
      └── WebSocket (/ws/game/, /ws/leaderboard/)
                │
                ▼
         ElastiCache Redis (Django Channels layer)
                │  broadcasts score updates to all connected clients
                ▼
         RDS PostgreSQL (game sessions, questions, results)
```

### Infrastructure Layout

```
AWS VPC (10.0.0.0/16)
│
├── Public Subnets  (10.0.101.0/24, 10.0.102.0/24)
│   └── NAT Gateway (single — cost optimised, see ADR-03)
│
└── Private Subnets (10.0.1.0/24, 10.0.2.0/24)
    ├── EKS Node Group  (2× t4g.small, ARM64 Graviton)
    ├── RDS PostgreSQL  (db.t4g.micro)
    └── ElastiCache Redis (cache.t4g.micro, TLS enabled)
```

### Identity — Zero Static Credentials

```
GitHub Actions → OIDC token → AWS STS AssumeRoleWithWebIdentity
                               → temporary creds (1hr TTL)
                               → scoped to this repo/branch only

EKS Pods → IRSA → per-component IAM roles
  game-service   → cloudops-dev-game-irsa-role   (read Secrets Manager)
  ESO            → cloudops-dev-eso-irsa-role    (read Secrets Manager)
  AWS LBC        → cloudops-dev-lbc-irsa-role    (manage NLB/load balancers)
```

### Secrets Flow

```
AWS Secrets Manager
├── cloudops-dev-postgres-secret  {host, port, db_name, username, password}
└── cloudops-dev-redis-secret     {host, port, password}
         │
         ▼  (IRSA-authenticated, no node credentials)
External Secrets Operator
         │
         ▼
Kubernetes Secret (game-redis-credentials)
         │  REDIS_URL = rediss://:password@host:6379
         ▼
game-service Pod (env var injected at container start)
```

---

## Technology Stack

| Layer | Technology | Version | Notes |
|---|---|---|---|
| Cloud | AWS | — | us-east-1 |
| Kubernetes | EKS | 1.36 | Managed control plane |
| Nodes | EC2 t4g.small | ARM64 Graviton | 2 nodes, ~20% cheaper than x86 |
| Application | Django + Daphne | 6.x | ASGI, WebSocket via Channels |
| Database | RDS PostgreSQL | 16.3 | db.t4g.micro, private subnets |
| Channel layer | ElastiCache Redis | 7.x | TLS, cache.t4g.micro |
| Secret management | External Secrets Operator | v1 API | Syncs from Secrets Manager |
| Image registry | Amazon ECR | — | ARM64 images, lifecycle policy |
| IaC | Terraform | >= 1.3 | Modular, S3 + DynamoDB remote state |
| CI/CD | GitHub Actions | — | OIDC auth, 7 single-purpose workflows |
| Load balancer | NLB + ingress-nginx | — | AWS LBC managed, ACM TLS |
| LB controller | AWS Load Balancer Controller | v3.4 | IRSA-authenticated |
| Container scanning | Trivy | 0.74+ | Blocks push on CRITICAL/HIGH CVEs |
| IaC scanning | Checkov | — | Scans Terraform on every PR |
| Cost estimation | Infracost | — | PR diff comments |
| Observability | kube-prometheus-stack | — | Prometheus + Grafana |
| Log aggregation | Loki | 3.6.7 | Standalone chart (not deprecated loki-stack) |
| Log shipping | Promtail | 3.5.x | DaemonSet, one per node |
| Governance | Cloud Custodian | — | EBS cleanup, NLB cleanup, ECR retention |
| RDS scheduling | GitHub Actions cron | — | Stop 10pm UTC, start 8am UTC daily |

---

## Repository Structure

```
cloudops_control_plane/
│
├── .github/workflows/
│   ├── 01-terraform-plan.yml    # PR: Django tests + Checkov + Infracost + tf plan
│   ├── 02-terraform-apply.yml   # Post-merge: apply saved plan
│   ├── 03-docker-build.yml      # Post-apply: Trivy scan → build ARM64 → push ECR
│   ├── 04-k8s-deploy.yml        # Post-build: full cluster deploy
│   ├── 05-finops-reporter.yml   # Monthly cron: cost report + Custodian cleanup
│   ├── 06-destroy.yml           # Manual: safe full teardown
│   └── 07-rds-schedule.yml      # Cron: stop 10pm UTC, start 8am UTC daily
│
├── bootstrap/
│   ├── backend/                 # S3 state bucket + DynamoDB lock table
│   └── iam/                     # GitHub OIDC provider + Actions role
│
├── terraform/
│   ├── environments/dev/
│   │   ├── main.tf              # Module calls
│   │   ├── locals.tf            # All resource names live here
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   └── Modules/
│       ├── vpc/                 # Custom VPC — full per-resource naming control
│       ├── eks/                 # EKS cluster + OIDC provider + node groups
│       ├── rds/                 # PostgreSQL + parameter group + Secrets Manager
│       ├── elasticache-redis/   # Redis cluster + subnet group + Secrets Manager
│       ├── iam-irsa/            # IRSA roles (game, ESO, LBC)
│       ├── security/            # Security groups per service
│       └── ecr/                 # ECR repository + lifecycle policy
│
├── services/
│   └── game-service/            # Django ASGI app (git submodule)
│
├── helm/
│   └── game-service/
│       ├── Chart.yaml
│       ├── values.yaml          # Defaults (overridden by configs/dev/)
│       └── templates/           # deployment, service, hpa
│
├── kubernetes/
│   ├── base/
│   │   ├── cluster-secret-store.yaml
│   │   └── network-policies/    # default-deny + explicit allow rules
│   └── overlays/dev/
│       ├── kustomization.yaml
│       ├── ingress.yaml         # game.therealblessing.com routing
│       └── externalsecret-redis.yaml
│
├── configs/dev/
│   └── values-game-service.yaml # Helm overrides for dev
│
├── kubernetes/monitoring/
│   ├── prometheus-values.yaml
│   └── loki-values.yaml
│
├── finops/
│   ├── automation/cost-report.py
│   └── reports/monthly.md       # Auto-updated 1st of every month
│
├── governance/
│   ├── checkov/checkov.yaml
│   └── custodian/
│       ├── ebs-cleanup.yaml
│       ├── unused-nlb.yaml
│       └── ecr-image-cleanup.yaml
│
└── docs/
    ├── architecture.md
    ├── decision.md              # 12 Architecture Decision Records
    ├── runbook.md
    ├── onboarding.md
    └── troubleshooting.md       # 17 real incidents documented
```

---

## CI/CD Pipeline

```
PR opened
  └── 01-terraform-plan
       ├── Django unit tests
       ├── Checkov IaC security scan
       ├── Infracost PR diff comment (shows cost impact before merge)
       └── terraform plan → artifact

Merged to main
  └── 02-terraform-apply
       ├── Restore secrets if pending-deletion
       └── terraform apply (saved plan)
            └── 03-docker-build
                 ├── Detect if game-service code changed
                 ├── Check ECR for existing image (fresh env detection)
                 ├── Build linux/arm64 image locally (no push yet)
                 ├── Trivy scan: CRITICAL+HIGH block push, SARIF → GitHub Security
                 └── Push to ECR: :sha, :short-sha, :latest
                      └── 04-k8s-deploy
                           ├── Resolve ACM/LBC/ESO ARNs dynamically from AWS
                           ├── Install ESO with IRSA annotation
                           ├── Apply ClusterSecretStore
                           ├── Apply Kustomize overlays
                           ├── Wait for Redis secret sync
                           ├── Install metrics-server
                           ├── Install AWS Load Balancer Controller
                           ├── Install ingress-nginx (NLB, HTTPS-only, HSTS)
                           ├── Deploy game-service (Helm --atomic)
                           └── Deploy monitoring (Prometheus + Grafana + Loki)

Every day at 10pm UTC
  └── 07-rds-schedule → stop RDS

Every day at 8am UTC
  └── 07-rds-schedule → start RDS

1st of every month at 8am UTC
  └── 05-finops-reporter
       ├── AWS Cost Explorer → monthly.md
       ├── Cloud Custodian: EBS + NLB + ECR cleanup
       └── Commit report [skip ci]

Manual trigger
  └── 06-destroy
       ├── Remove ExternalSecret finalizers
       ├── Helm uninstall all releases (triggers NLB deprovisioning)
       ├── Delete namespaces with timeout
       ├── Force-delete ECR images + Secrets Manager secrets
       └── terraform destroy
```

---

## Key Engineering Decisions

Every decision is documented with full context in [docs/decision.md](docs/decision.md). Highlights:

**Why ARM64 (t4g.small) over x86?**
~20% cheaper with comparable performance. Trade-off: images must be built with `docker buildx --platform linux/arm64`. Deploying an x86 image to ARM64 nodes silently produces `exec format error` — a real incident we hit and documented.

**Why a custom VPC module over the community module?**
`terraform-aws-modules/vpc` derives all sub-resource names from a single `name` input — you get no individual resource naming control. For a project that prioritises clear AWS console identification, we wrote a custom module accepting explicit names for every resource.

**Why NLB over ALB?**
Layer 4, lower cost, native WebSocket support. Trade-off: NLB can't add `X-Forwarded-Proto` headers, so HTTP→HTTPS redirects via nginx create infinite loops. Solution: remove port 80 entirely. All traffic uses HTTPS only; HSTS enforces this in browsers.

**Why External Secrets Operator over Sealed Secrets?**
Sealed Secrets solves "how to commit secrets safely to Git" — a problem that doesn't exist when you have AWS Secrets Manager. ESO syncs live secrets with IRSA authentication. No secrets in Git, no manual encryption.

**Why Trivy as a build gateway?**
Scanning after push means a vulnerable image is already in ECR before findings appear. Building locally, scanning, then pushing only on a clean result means no vulnerable image ever reaches ECR or the cluster.

**Why `latest` tag in deploys instead of commit SHA?**
Config-only changes (Helm values, K8s manifests) don't trigger image builds. If the deploy used the commit SHA, it would reference a tag that was never built. `latest` always points to the last successfully built and scanned image.

---

## Cost Breakdown

| Resource | Type | Monthly |
|---|---|---|
| EKS control plane | Managed | ~$7.20 |
| EC2 nodes | 2× t4g.small ARM64 | ~$11.68 |
| RDS PostgreSQL | db.t4g.micro | ~$2.69* |
| ElastiCache Redis | cache.t4g.micro | ~$2.16 |
| NAT Gateway | Single AZ | ~$1.00 |
| Secrets Manager | 2 secrets | ~$0.80 |
| ECR storage | ~1GB | ~$0.10 |
| **Total** | | **~$25.63** |

*RDS stopped 10pm–8am daily and all weekend via `07-rds-schedule.yml` (~60% cost reduction from 24/7 rate of ~$6.72)

AWS Budget alerts fire at 80% ($24) and 100% ($30).

---

## Security Posture

| Control | Implementation |
|---|---|
| Zero static credentials | OIDC for CI/CD, IRSA for pods — no IAM access keys anywhere |
| Network isolation | All compute in private subnets, default-deny network policies |
| Secret management | AWS Secrets Manager + ESO — no secrets in Git |
| Container scanning | Trivy blocks push on CRITICAL/HIGH CVEs, results in GitHub Security tab |
| IaC scanning | Checkov on every PR, soft-fail with findings in workflow annotations |
| TLS | ACM wildcard cert, NLB termination, HSTS max-age=31536000 |
| HTTPS-only | Port 80 removed entirely — NLB only listens on 443 |
| Least privilege | Per-component IAM roles scoped to exact resource needs |
| Image provenance | ARM64-only builds, SHA tags for exact commit traceability |

---

## Observability

| Signal | Tool | Access |
|---|---|---|
| Metrics | Prometheus | `kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring` |
| Dashboards | Grafana | `kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring` |
| Logs | Loki via Grafana | Explore → `{namespace="game-dev"}` |
| K8s state | kube-state-metrics | Scraped by Prometheus automatically |
| Node metrics | node-exporter | DaemonSet, one per node |

Grafana credentials: `admin / prom-operator`

---

## Quick Start

### Prerequisites

```bash
aws --version       # >= 2.0
terraform --version # >= 1.3
kubectl version     # >= 1.28
helm version        # >= 3.0
python3 --version   # >= 3.10
```

### Bootstrap (one-time per AWS account)

```bash
# Step 1 — S3 state backend + DynamoDB lock table
cd bootstrap/backend
terraform init && terraform apply

# Step 2 — GitHub OIDC provider + Actions role
cd ../iam
terraform init && terraform apply \
  -var="github_repo=nanafilbert/cloudops_control_plane"

# Step 3 — Add role ARN to GitHub Secrets
terraform output github_actions_role_arn
# GitHub → Settings → Secrets → Actions → GH_OIDC_ROLE_ARN
```

### Deploy

Push to `main` — the pipeline handles everything automatically.

### Access

```bash
# Live game
open https://game.therealblessing.com

# Grafana monitoring
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
open http://localhost:3000  # admin / prom-operator

# Live logs
kubectl logs -f -l app=game-service -n game-dev

# RDS manual control
# GitHub → Actions → RDS Off-Hours Schedule → Run workflow → stop/start
```

---

## Known Limitations

| Limitation | Reason | Production fix |
|---|---|---|
| Single replica game-service | Cost | HPA configured, just add nodes |
| Single NAT Gateway | ~$32/month saving | One NAT GW per AZ |
| No RDS automated backups | `backup_retention_period = 0` | Set to 7+ days |
| Grafana data not persisted | No EBS CSI driver installed | Add EBS CSI + PVC |
| t4g.small 22-pod ceiling | ENI IP limits, not CPU/RAM | Upgrade to t4g.medium |
| HTTP disabled entirely | NLB can't redirect L4 | Use ALB for HTTP redirect |

---

## Real Incidents Documented

Every significant failure during this build is documented in [docs/troubleshooting.md](docs/troubleshooting.md) with root cause and resolution:

- `exec format error` — ARM64 vs x86 architecture mismatch in CI
- Pod IP exhaustion on t4g.small (22-pod ceiling, not CPU/memory)
- NLB TLS passthrough causing nginx 400 errors (`targetPorts.https=http`)
- Infinite HTTPS redirect loop behind Layer 4 NLB
- ExternalSecret finalizer deadlock blocking namespace deletion
- Loki v2.9.3 incompatible with Grafana 13 health check API
- Redis security group referencing wrong EKS SG (custom vs cluster SG)
- LBC service account annotated with ACM cert ARN instead of IAM role ARN
- pip vendored SBOM causing Trivy false positives for old setuptools/msgpack
- WSL DNS resolver (`10.255.255.254`) blocking EKS endpoint resolution
- GitHub OIDC failure after AWS account migration

---

## Documentation

| Document | Contents |
|---|---|
| [Architecture](docs/architecture.md) | Component design, networking, security groups, data flows |
| [Decision Records](docs/decision.md) | 12 ADRs for every major engineering choice |
| [Runbook](docs/runbook.md) | Day-2 operational procedures |
| [Onboarding](docs/onboarding.md) | Local development setup, concepts explained |
| [Troubleshooting](docs/troubleshooting.md) | 17 real incidents with root causes |

---

## Project Timeline

| Phase | What Was Built |
|---|---|
| EC2 baseline | Two-server architecture with WireGuard VPN tunnel |
| Kubernetes migration | EKS cluster, custom Terraform modules, RDS, Redis |
| Security hardening | OIDC, IRSA, zero static credentials, network policies |
| Observability | Prometheus, Grafana, Loki, Promtail |
| Supply chain security | Trivy container scanning as build gateway |
| HTTPS + domain | NLB, ingress-nginx, ACM wildcard cert, HSTS |
| FinOps | Cloud Custodian, RDS off-hours, Infracost PR comments |
| Documentation | 12 ADRs, runbooks, 17 real incident troubleshooting guide |

---

## What This Project Demonstrates

- **Modular Terraform** — custom modules, resource-specific naming, remote state, environment isolation
- **Zero static credentials** — OIDC for CI/CD, IRSA for pods, no IAM keys anywhere in the system
- **Supply chain security** — Trivy as a hard build gateway, Checkov IaC scanning, results in GitHub Security tab
- **Real incident history** — 17 documented failures with root causes and resolutions — not a tutorial setup
- **Cost-aware architecture** — every decision weighed against a $30/month budget constraint
- **Operational readiness** — runbooks, Grafana dashboards, Loki logs, RDS scheduling, FinOps reporting
- **Secure by design** — network policies, HTTPS-only, HSTS, private subnets, least-privilege IAM

---

*Every decision in this repository was made consciously, documented, and can be justified. This is what production infrastructure engineering actually looks like — trade-offs, incidents, constraints, and deliberate choices.*