# Architecture

Technical architecture of cloudops_control_plane — how every component works, why it was designed the way it was, and how the pieces fit together.

---

## The Application Layer

### Django + Daphne (ASGI)

The game service runs Django with Daphne as the ASGI server. ASGI (Asynchronous Server Gateway Interface) supports long-lived connections like WebSockets alongside standard HTTP requests.

```
Daphne (port 8000)
├── HTTP connections  → Django views (standard request-response)
└── WebSocket connections → Django Channels consumers (persistent, bidirectional)
```

**Why this matters for health probes:** HTTP probes send a full request and expect an HTTP response — but Django's `ALLOWED_HOSTS` must accept the probe's Host header. Behind a Kubernetes Service, the probe comes from the kubelet using the pod IP, not the domain name. We use `tcpSocket` probes instead — they just check if port 8000 is open, with no HTTP handshake and no Host header validation.

### Django Channels and Redis

Real-time features require pushing messages to multiple connected clients simultaneously. Django Channels adds WebSocket support and introduces the channel layer — a shared message bus.

```
Player answers a question
    ↓
GameConsumer.receive() validates answer, updates score in PostgreSQL
    ↓
channel_layer.group_send("leaderboard", {score update})
    ↓
Redis pub/sub broadcasts to all listeners in the group
    ↓
LeaderboardConsumer.leaderboard_update() runs for every connected client
    ↓
All browsers receive the updated leaderboard simultaneously
```

Without Redis, channel groups don't work across multiple processes. With a single-replica deployment, an in-memory channel layer technically works — but Redis is used because it's the production-appropriate choice and allows future horizontal scaling without code changes.

---

## Network Architecture

### VPC Design

```
VPC (10.0.0.0/16)
│
├── Public Subnets (10.0.101.0/24, 10.0.102.0/24)
│   ├── NAT Gateway — outbound internet for private resources
│   └── NLB — receives inbound traffic from internet
│
└── Private Subnets (10.0.1.0/24, 10.0.2.0/24)
    ├── EKS worker nodes
    ├── RDS PostgreSQL
    └── ElastiCache Redis
```

Resources in private subnets have no public IP. They reach the internet via NAT Gateway but cannot be reached directly from the internet.

### Security Group Architecture

```
NLB SG
└── ingress: 443 from 0.0.0.0/0
└── egress: all

EKS cluster SG (auto-created by EKS, attached to all nodes)
└── ingress: cluster-internal traffic
└── egress: all

RDS SG (cloudops-dev-rds-sg)
└── ingress: 5432 from EKS CLUSTER SG only
    ↑ NOTE: this is module.eks.node_security_group_id, not cloudops-dev-eks-sg

Redis SG (cloudops-dev-redis-sg)
└── ingress: 6379 from EKS CLUSTER SG only
```

**Critical distinction:** EKS creates its own cluster security group automatically and attaches it to all nodes. This is separate from any custom security groups you define. When game-service pods connect to RDS or Redis, the traffic originates from the EKS cluster SG — not from `cloudops-dev-eks-sg`. RDS and Redis security groups must reference `module.eks.node_security_group_id`. Confusion between these two SGs caused a real incident where Redis connections silently dropped — see Troubleshooting Incident 09.

### Traffic Flow: Inbound

```
1. Browser requests https://game.therealblessing.com

2. DNS: game.therealblessing.com
   → CNAME → cloudops-dev-nlb-xxx.elb.us-east-1.amazonaws.com
   → resolves to NLB IP addresses

3. Browser establishes TLS connection to NLB IP:443
   NLB presents ACM wildcard cert (*.therealblessing.com)
   TLS handshake completes — certificate private key never leaves AWS

4. NLB decrypts TLS, forwards plain HTTP to a worker node on a NodePort

5. Worker node routes to ingress-nginx pod

6. ingress-nginx evaluates the request:
   Host: game.therealblessing.com → matches ingress rule
   → game-service Service → game-service Pod port 8000

7. Django/Daphne processes the request, returns response
```

### Why targetPorts.https=http Matters

This was one of the most confusing incidents in the build. By default:

```
NLB port 443
  → Target group
    → NodePort
      → Service port 443 → maps to container port "https"
        → nginx expects TLS here
          → receives plain HTTP from NLB
            → 400 Bad Request
```

The fix: `controller.service.targetPorts.https=http`

```
NLB port 443 (TLS terminated here)
  → NodePort
    → Service port 443 → maps to container port "http"
      → nginx expects plain HTTP
        → receives plain HTTP from NLB
          → routes normally ✅
```

---

## Identity and Access Architecture

### GitHub Actions OIDC Trust Chain

```
1. Workflow starts
2. GitHub mints a JWT for this specific workflow run
   Claims: repository name, branch, actor, ref
   Signed with GitHub's private key

3. Workflow calls AWS STS:
   AssumeRoleWithWebIdentity(
     RoleArn = "arn:aws:iam::...:role/github-actions-oidc-role",
     WebIdentityToken = <GitHub JWT>
   )

4. AWS STS validates the JWT:
   a. Fetches GitHub's public key from JWKS endpoint
   b. Verifies JWT signature
   c. Checks trust policy conditions:
      aud = "sts.amazonaws.com" ✓
      sub = "repo:nanafilbert/cloudops_control_plane:ref:refs/heads/main" ✓
   d. Issues temporary credentials (1 hour TTL)
```

The trust policy controls which workflows can assume the role. A workflow from any other repository cannot assume it.

### IRSA (IAM Roles for Service Accounts)

IRSA uses the same OIDC mechanism inside the cluster:

```
1. Pod starts with annotated service account:
   eks.amazonaws.com/role-arn: arn:aws:iam::...:role/cloudops-dev-eso-irsa-role

2. EKS pod identity webhook injects a projected volume with a ServiceAccount token
   and environment variables pointing to the token file

3. When the pod calls an AWS API:
   AWS SDK reads the projected token
   Calls STS AssumeRoleWithWebIdentity
   Receives temporary credentials scoped to cloudops-dev-eso-irsa-role
```

Per-component IAM roles with minimum permissions:
- `game-service` → `secretsmanager:GetSecretValue` on postgres + redis secrets
- `external-secrets` → `secretsmanager:GetSecretValue, DescribeSecret` on all secrets
- `aws-load-balancer-controller` → full EC2, ELB, ACM, WAF permissions

---

## Storage and State Architecture

### Terraform Remote State

```
S3 bucket (cloudops-dev-terraform-state-{account_id})
├── Encryption: AES256
├── Versioning: enabled (state recoverable if corrupted)
└── Key: environments/dev/terraform.tfstate

DynamoDB table (cloudops-dev-terraform-locks)
└── Lock mechanism:
    terraform apply → acquires lock → modifies state → releases lock
    concurrent apply → tries to acquire lock → fails with error
```

### ECR Image Lifecycle

```
cloudops-dev-game-service repository
├── :{full-git-sha}     — exact commit traceability
├── :{short-git-sha}    — human-readable
└── :latest             — deploy target (points to last clean build)

Lifecycle policy: retain last 10 images, expire older ones
```

---

## Observability Architecture

### Metrics Pipeline

```
node-exporter (DaemonSet) — node-level metrics (CPU, memory, disk, network)
kube-state-metrics — Kubernetes object metrics (pods, deployments, HPA)
Prometheus (scrapes all targets every 10 seconds)
  └── retention: 24 hours (no PVC — ephemeral, lost on restart)
Grafana — queries Prometheus, renders dashboards
```

No PVC for Prometheus or Grafana — no EBS CSI driver installed (saves pod slots and cost). For production: install the EBS CSI driver, create a StorageClass, enable persistence.

### Logging Pipeline

```
All pods write to stdout/stderr
Container runtime writes logs to node filesystem
Promtail (DaemonSet) reads logs from node filesystem
  └── attaches labels: namespace, pod, container, app
  └── ships to Loki
Loki indexes logs by label, stores on pod filesystem (/tmp/loki — ephemeral)
Grafana Explore → Loki data source
  └── Query: {namespace="game-dev"}
```

---

## Module Design

### Why All Resource Names Live in `locals.tf`

Every resource name is defined in `terraform/environments/dev/locals.tf`:

```hcl
base    = "${local.project}-${local.env}"       # cloudops-dev
vpc_name = "${local.base}-vpc"                  # cloudops-dev-vpc
eks_cluster_name = "${local.base}-eks-cluster"  # cloudops-dev-eks-cluster
rds_identifier = "${local.base}-postgres-db"    # cloudops-dev-postgres-db
```

Changing the project name or environment requires editing two lines. Everything cascades automatically.

### Module Responsibility Boundaries

| Module | Owns | Outputs |
|---|---|---|
| `vpc` | VPC, subnets, route tables, IGW, NAT | vpc_id, subnet IDs |
| `eks` | Cluster, node group, OIDC provider | cluster_name, endpoint, node_sg_id |
| `security` | Security groups per service | SG IDs |
| `rds` | DB instance, parameter group, secret | endpoint, secret_arn |
| `elasticache-redis` | Replication group, subnet group, secret | endpoint, secret_arn |
| `iam-irsa` | IAM role + trust policy | role_arn |
| `ecr` | Repository, lifecycle policy | repository_url |

No module directly references another module's internal resources — all communication via outputs and variables. This makes modules independently testable.

---

## Pod Capacity Planning

`t4g.small` maximum pods: 3 ENIs × 4 IPs = 11 per node. With 2 nodes: 22 pod ceiling.

Current stack at steady state:

| Namespace | Pods | Notes |
|---|---|---|
| kube-system | 7 | aws-node×2, coredns×2, kube-proxy×2, metrics-server×1 |
| kube-system | 1 | aws-load-balancer-controller (replicaCount=1) |
| external-secrets | 1 | controller only (webhook + cert-controller disabled) |
| ingress-nginx | 1 | controller (replicaCount=1) |
| game-dev | 1 | game-service |
| monitoring | 6 | grafana, operator, kube-state-metrics, node-exporter×2, prometheus |
| logging | 3 | loki, promtail×2 (canary disabled) |
| **Total** | **21** | 1 slot free for transient jobs |

Components deliberately reduced to fit within ceiling:
- LBC: 1 replica (default is 2)
- ESO: controller only, no webhook or cert-controller
- Loki: canary disabled (saves 2 pods)
- No Cluster Autoscaler (not needed, saves 1 pod)