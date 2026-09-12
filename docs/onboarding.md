# Onboarding Guide

Welcome to cloudops_control_plane. This guide gets you from zero to a running local development environment, explains every tool you will interact with, and prepares you to understand what happens when you push a change.

---

## What You Are Working With

**The application** (`services/game-service/`) is a Django ASGI app. It uses Daphne — not `runserver` — because it serves WebSocket connections for real-time game state. Django Channels routes WebSocket messages through Redis, which acts as a channel layer. When one player scores a point, all connected clients receive the leaderboard update simultaneously because Redis broadcasts the channel group message to every listener.

**The platform** (everything else in this repo) is the AWS infrastructure, CI/CD pipeline, Kubernetes configuration, and operational tooling that makes the application accessible at `https://game.therealblessing.com`.

**The relationship:** the application has no knowledge of Kubernetes. It reads database credentials from AWS Secrets Manager at startup, connects to Redis via a URL injected as an environment variable, and serves HTTP/WebSocket traffic on port 8000. Everything else — TLS, load balancing, secret management, auto-restart on crash — is handled by the platform.

---

## Prerequisites

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
aws --version   # should show 2.x

# Terraform
wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform_1.9.0_linux_amd64.zip && sudo mv terraform /usr/local/bin/
terraform --version

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Python
python3 --version   # should show 3.10+
```

---

## Clone the Repository

This repo uses a git submodule for the game service. Clone recursively:

```bash
git clone --recurse-submodules https://github.com/nanafilbert/cloudops_control_plane.git
cd cloudops_control_plane
```

If you forgot `--recurse-submodules`:
```bash
git submodule update --init --recursive
```

---

## Run the Game Locally

You can run the game without any Kubernetes or AWS:

```bash
cd services/game-service

python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Start local Redis
docker run -d --name redis -p 6379:6379 redis:7-alpine

export REDIS_URL=redis://localhost:6379
export DEBUG=true

python manage.py migrate
python manage.py seed_questions
python manage.py seed_more_questions

# MUST use Daphne — not runserver
# runserver is WSGI only; WebSockets will not work
daphne -p 8000 trivia.asgi:application
```

Open http://localhost:8000.

**Why Daphne?** Django's built-in `runserver` is a WSGI server — it handles standard HTTP but has no concept of WebSocket connections. Daphne is an ASGI server that handles both HTTP and WebSocket on the same port. In production, the Kubernetes deployment runs Daphne too.

---

## Understanding the Infrastructure

### Where things live in AWS

```
VPC (cloudops-dev-vpc, 10.0.0.0/16)
├── Public subnets — the NAT Gateway lives here
│   Outbound internet access for private resources flows through here
└── Private subnets — everything else
    ├── EKS worker nodes (the VMs running your pods)
    ├── RDS PostgreSQL (not accessible from the internet)
    └── ElastiCache Redis (not accessible from the internet)
```

Resources in private subnets have no public IP addresses. The only entry point from the internet is the NLB, which forwards traffic to EKS nodes on specific ports.

### How secrets get into pods

This replaces the naive "put credentials in environment variables" approach:

1. **Terraform** creates RDS and Redis and stores credentials in AWS Secrets Manager
2. **External Secrets Operator** is configured with a `ClusterSecretStore` pointing to Secrets Manager using IRSA credentials
3. An `ExternalSecret` resource tells ESO: fetch `cloudops-dev-redis-secret` and create a Kubernetes Secret called `game-redis-credentials`
4. The game-service `Deployment` references this Kubernetes Secret as an environment variable
5. The container starts with `REDIS_URL` already set — the app just reads an env var

### How GitHub Actions authenticates to AWS

No AWS access keys are stored anywhere:

1. The workflow requests an OIDC token from GitHub
2. The token is presented to AWS STS via `AssumeRoleWithWebIdentity`
3. AWS validates the token signature using GitHub's public key
4. AWS checks the trust policy (correct repo, correct branch)
5. AWS returns temporary credentials valid for 1 hour

This happens transparently via `aws-actions/configure-aws-credentials`.

### How the image build works

1. Checks if `services/game-service/**` changed — if not, skips the build
2. Also checks if ECR has any images — if empty (fresh cluster), must build
3. Builds for `linux/arm64` (the architecture of t4g.small ARM64 nodes)
4. Runs Trivy scan — CRITICAL/HIGH findings block the push
5. Pushes three tags: full SHA, 7-char short SHA, and `latest`

---

## Making a Change

### Infrastructure change

```bash
git checkout -b feat/my-change
# edit terraform files
git push origin feat/my-change
# open PR — plan workflow runs automatically
# merge — apply workflow runs automatically
```

### Application change

```bash
# edit files in services/game-service/
# test locally with Daphne
git push origin feat/my-change
# open PR, merge — pipeline builds new ARM64 image and deploys it
```

### Kubernetes/Helm config change

```bash
# edit manifests in kubernetes/ or values in configs/dev/
git push origin main
# deploy workflow runs using the existing image
```

---

## Common Operations

```bash
# See what is running
kubectl get pods -A
kubectl get pods -n game-dev
kubectl get svc -n ingress-nginx
kubectl get ingress -n game-dev

# Follow application logs
kubectl logs -f -l app=game-service -n game-dev

# Access Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# http://localhost:3000  admin / prom-operator

# Check costs this month
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --query 'ResultsByTime[0].Total.UnblendedCost.Amount' \
  --output text
```

---

## Setting Up for Terraform Operations

```bash
aws configure
# Enter Access Key ID, Secret Access Key, region (us-east-1)

aws sts get-caller-identity   # verify

cd terraform/environments/dev
terraform init
terraform plan
```

Read the plan carefully. `~` = modify in place. `-/+` = destroy and recreate (check if intentional). `+` = new resource.

---

## Things That Will Confuse You Until They Don't

**"Why does the workflow use `latest` and not the commit SHA?"**
If you push a config change (not application code), the build workflow skips — no new image is built. If the deploy workflow tried to use the commit SHA, it would look for a tag that was never built and fail with `ImagePullBackOff`. `latest` always points to the last successfully scanned and pushed image.

**"Why can't I just use `python manage.py runserver`?"**
The game uses WebSockets. `runserver` is WSGI — it doesn't support persistent WebSocket connections. HTTP requests will work but the actual game won't because the WebSocket will fail to establish.

**"Why does the pod count matter so much?"**
`t4g.small` has a hard limit of 11 pods per node via ENI IP allocation — not CPU or memory. With 2 nodes, the ceiling is 22 pods. Exceeding it causes pods to stay `Pending` indefinitely regardless of available CPU and memory.

**"Why did `kubectl apply` say `resource mapping not found` when the CRD exists?"**
kubectl caches the API server resource list locally. After installing a new CRD (like ESO's ClusterSecretStore), kubectl doesn't immediately know about it. Clear the cache:
```bash
rm -rf ~/.kube/cache/discovery/
```

**"Why is Grafana empty after a cluster rebuild?"**
Grafana has no persistent storage — no PVC, no EBS volume. Every cluster rebuild starts with a clean Grafana. Add Prometheus and Loki data sources manually after each rebuild.

**"Why are there 3 tags on every Docker image?"**
Full SHA (for exact traceability), short SHA (for human readability), and `latest` (for the deploy target). They all point to the same image — no extra storage cost. The ECR lifecycle policy retains the last 10 images and expires older ones.

---

## Getting Help

1. Read `docs/troubleshooting.md` first — it documents every significant failure during this build
2. Check `docs/decision.md` for why things are the way they are
3. Run `kubectl get events -n game-dev --sort-by='.lastTimestamp'`
4. Check the GitHub Actions workflow logs — each step is labelled