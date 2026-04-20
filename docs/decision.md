# Architecture Decision Records (ADRs)

## ADR 001: 1‑Replica Demo Configuration
**Context:** Need to demonstrate high availability concepts without high cost.  
**Decision:** Run each microservice with 1 replica by default, but HPA scales to 3 under load.  
**Consequences:** Cost reduced ~50%; not truly resilient but acceptable for demo.

## ADR 002: OIDC over IAM Keys
**Context:** Eliminate long‑lived credentials (access keys).  
**Decision:** 
- GitHub Actions assumes an IAM role via OIDC federation.
- Pods use IRSA (IAM Roles for Service Accounts) to access AWS services.  
**Consequences:** No secrets stored in GitHub or Kubernetes. Credentials are short‑lived.

## ADR 003: Managed RDS over Self‑Hosted PostgreSQL
**Context:** Production‑grade database without operational overhead.  
**Decision:** Use AWS RDS (PostgreSQL) with `db.t4g.micro` instance.  
**Benefits:** Automated backups, point‑in‑time recovery, patching, failover.  
**Cost:** Minimal – ~$15/month.

## ADR 004: Rolling Updates over Blue/Green
**Context:** Deploy new game versions without downtime and without doubling cost.  
**Decision:** Use Kubernetes rolling updates (default `strategy`).  
**Consequences:** Zero downtime, no extra cost. Rollback via `kubectl rollout undo`.

## ADR 005: Cost Budget Alert at $30
**Context:** Keep demo environment under $30/month.  
**Decision:** FinOps reporter fails the workflow if 30‑day cost exceeds $30.  
**Consequences:** Immediate visibility; prevents surprise bills.

## ADR 006: Kustomize + Helm Separation
**Context:** Need both static cluster resources and templated application deployments.  
**Decision:** Use Kustomize for cluster‑bootstrapping (namespaces, network policies, HPAs) and Helm for versioned microservices.  
**Consequences:** Clear separation of concerns; no "Helm soup".