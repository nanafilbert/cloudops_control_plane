# System Architecture

## High-Level Traffic Flow
[User] → Route53 → ALB → Ingress-Nginx → K8s Service (ClusterIP) → Game Pods → RDS (PostgreSQL)


## Network Topology
- VPC across 2 Availability Zones (us-east-1a, us-east-1b)
- Public subnets: Load Balancer, NAT Gateway
- Private subnets: EKS managed nodes, RDS instance
- NAT Gateway in a single AZ (cost optimisation)

## Components
| Component |         Technology                      |Purpose |
|-----------|-----------                              |---------|
| Compute   | EKS (Kubernetes 1.28)                     Container orchestration |
| Database  | RDS PostgreSQL (db.t4g.micro)           | Game state, backups (7‑day retention) |
| Secrets   | AWS Secrets Manager + External Secrets Operator | No plaintext secrets |
| Identity  | GitHub OIDC + IRSA                      | Zero‑trust, no static credentials |
| Observability | Prometheus, Grafana, Loki           | Metrics, dashboards, logs |
| Governance | Cloud Custodian + Python cost reporter | FinOps, idle resource cleanup |

## Scaling Strategy
- Horizontal Pod Autoscaler (HPA): scales from 1 to 3 replicas when CPU > 70%
- EKS node group: min 1, max 2 (t3.medium)

## Failure Recovery
- Pod termination → automatically rescheduled by ReplicaSet
- Node drain → workloads redistributed to remaining node
- RDS automated backups (daily, 7‑day retention)