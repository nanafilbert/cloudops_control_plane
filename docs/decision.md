# Architecture Decision Records (ADRs)

Every significant engineering decision made during the design and build of cloudops_control_plane is recorded here. Each ADR captures the context, the decision, and the consequences — including trade-offs consciously accepted.

These are not theoretical decisions. Every one was made under real constraints: a $30/month budget, a Free Tier AWS account with instance restrictions, and a hard pod ceiling of 22 on t4g.small nodes.

---

## ADR-01: Custom VPC Module Over Community Module

**Status:** Accepted

### Context

`terraform-aws-modules/vpc` is widely used and well-maintained. The problem: it derives all sub-resource names from a single `name` input. Every subnet gets named `${name}-private-us-east-1a`, every route table `${name}-private`. You have no control over individual resource names. When looking at the AWS console with 30 resources starting with the same prefix, identifying what each does requires clicking into it.

### Decision

Write a custom VPC module accepting explicit name variables for every resource. All names are defined in `locals.tf` derived from a consistent base:

```hcl
base                 = "${local.project}-${local.env}"   # cloudops-dev
vpc_name             = "${local.base}-vpc"
public_subnet_names  = ["${local.base}-public-subnet-1a", "${local.base}-public-subnet-1b"]
private_subnet_names = ["${local.base}-private-subnet-1a", "${local.base}-private-subnet-1b"]
```

### Consequences

**Benefits:** Every resource in the AWS console is immediately identifiable. Changing project or environment requires editing two lines in `locals.tf`. All sub-resources cascade automatically.

**Trade-offs:** More Terraform code to maintain. We own the bug surface for VPC creation logic the community module handles automatically. Hit a real bug — `single_nat_gateway` variable was declared but not wired into the resource count, silently creating the wrong number of NAT gateways.

---

## ADR-02: Zero Static Credentials (OIDC + IRSA)

**Status:** Accepted

### Context

The common approach — IAM user with access keys stored in GitHub Secrets — creates several problems: keys don't expire unless manually rotated, a leaked key gives persistent AWS access, and rotation requires coordinated updates with a breakage window.

Inside the cluster, mounting AWS credentials as environment variables means they appear in pod specs, etcd, and `kubectl describe` output.

### Decision

**GitHub Actions → AWS:** Configure an OIDC identity provider in AWS IAM for GitHub. Each workflow requests a short-lived OIDC token, presents it to AWS STS via `AssumeRoleWithWebIdentity`, and receives temporary credentials valid for 1 hour. The trust policy is scoped to a specific repository and branch.

**Pods → AWS (IRSA):** The EKS cluster has its own OIDC provider. Each component that needs AWS access gets its own IAM role with the minimum required permissions. The service account is annotated with the role ARN; the EKS pod identity webhook injects temporary credentials.

```
# No long-lived credentials anywhere:
# - Not in GitHub Secrets
# - Not in Kubernetes Secrets
# - Not in pod environment variables
# - Not in .env files
```

### Consequences

**Benefits:** No credentials to rotate or leak. Blast radius of compromise is limited to 1-hour temporary credentials. CloudTrail shows exactly which role made each API call.

**Trade-offs:** More complex setup. Debugging auth failures requires checking multiple layers. Real incident: LBC service account annotated with the ACM cert ARN instead of the IAM role ARN — causing `ValidationError: Request ARN is invalid` in every LBC reconciliation loop until identified.

---

## ADR-03: Single NAT Gateway

**Status:** Accepted

### Context

AWS best practice for production: one NAT Gateway per AZ. If an AZ fails, private resources in surviving AZs retain outbound internet access. Each NAT Gateway costs ~$32/month in hourly and data processing charges.

### Decision

Deploy a single NAT Gateway in `us-east-1a` shared across both private subnets.

### Consequences

**Benefits:** Saves ~$32/month — the difference between being within budget and over it.

**Trade-offs:** AZ-level failure loses outbound connectivity for the entire cluster. Acceptable for development; unacceptable for production.

---

## ADR-04: Network Load Balancer Over Application Load Balancer

**Status:** Accepted

### Context

ALB (Layer 7): understands HTTP, can inspect headers, add `X-Forwarded-Proto`, perform redirects. NLB (Layer 4): operates on TCP, lower latency, cheaper, native WebSocket support, preserves client IP.

The application uses WebSockets for real-time game state. NLBs pass TCP connections through without interference.

### Decision

Use NLB with ingress-nginx as the HTTP-aware layer inside the cluster. TLS terminates at the NLB using ACM. ingress-nginx receives plain HTTP.

### Consequences

**Benefits:** Lower cost, lower latency, native WebSocket support.

**Trade-offs:** NLB cannot add `X-Forwarded-Proto` — it doesn't inspect HTTP. This caused a real production incident (see ADR-05 and Troubleshooting Incident 12).

---

## ADR-05: HTTPS-Only — No Port 80 Listener

**Status:** Accepted — after real incident

### Context

Standard HTTPS setup: accept HTTP on port 80 and redirect to HTTPS on port 443. First attempt used `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"`. This caused `ERR_TOO_MANY_REDIRECTS`.

**Root cause:** The NLB operates at Layer 4 and does not add `X-Forwarded-Proto: https`. When nginx receives a request, it has no way to know the original client used HTTPS — from nginx's perspective every request arrives as plain HTTP from the NLB. With `force-ssl-redirect` enabled, nginx always redirects to HTTPS. The browser follows it, hits port 443, the NLB decrypts and forwards plain HTTP to nginx, nginx sees plain HTTP again — loop.

Additionally, `controller.service.targetPorts.https=http` was required. Without it, the NLB's port 443 listener mapped to nginx's internal HTTPS container port which expects TLS-encrypted traffic — nginx received plain HTTP on a port configured for TLS and returned 400 Bad Request.

### Decision

Remove port 80 from the NLB listener entirely. The NLB only listens on port 443. HSTS enforces HTTPS in browsers after the first visit:

```yaml
controller.config.hsts: "true"
controller.config.hsts-max-age: "31536000"
controller.config.hsts-include-subdomains: "true"
```

### Consequences

**Benefits:** No redirect loops, no insecure entry point.

**Trade-offs:** Users attempting `http://game.therealblessing.com` get connection refused rather than a redirect. HSTS and modern browser behaviour mitigates this in practice.

---

## ADR-06: ARM64 Graviton Nodes

**Status:** Accepted — with documented incident

### Context

ARM64 (t4g) vs x86 (t3): ~20% cheaper for equivalent specs. `t4g.small` at $0.0168/hr vs `t3.small` at $0.0208/hr. For 2 nodes over a month — ~$6 saved, meaningful at a $30 total budget.

Trade-off: every Docker image must explicitly target `linux/arm64`. Standard `docker build` on a GitHub Actions runner (x86) produces an x86 image. Deploying that to ARM64 nodes produces `exec format error` — the pod shows status `Running` before immediately crashing, because the format incompatibility only surfaces at execution time.

AWS Free Tier blocked `t4g.medium` when we tried to upgrade for pod capacity: `InvalidParameterCombination: The specified instance type is not eligible for Free Tier`. This forced us to solve pod capacity through architectural decisions rather than simply scaling up.

### Decision

Use `t4g.small` ARM64 nodes. Mandate `docker buildx --platform linux/arm64` for all builds.

### Consequences

**Benefits:** ~20% cost reduction per node.

**Trade-offs:** All CI/CD must be configured for ARM64. `exec format error` is a real and confusing failure mode when the platform flag is missing.

---

## ADR-07: Image Tag Strategy — SHA Build, Latest Deploy

**Status:** Accepted — after real incident

### Context

The CI/CD chain has two workflows: `03-docker-build.yml` builds and pushes images, `04-k8s-deploy.yml` deploys them. The build workflow only runs when `services/game-service/**` changes — skipped for config-only changes.

If the deploy workflow used the commit SHA as the image tag, a config-only push would attempt to deploy a SHA that was never built, resulting in `ImagePullBackOff: not found`. This happened in production.

### Decision

- Build workflow pushes three tags: `:sha`, `:short-sha`, and `:latest`
- Deploy workflow uses `:latest`
- `latest` always points to the last successfully built and Trivy-scanned image

### Consequences

**Benefits:** Config changes deploy without triggering unnecessary builds. Fresh environments bootstrap without manual intervention.

**Trade-offs:** The running image isn't directly traceable from the deployed tag name alone — you need to inspect the image manifest for the SHA. Acceptable for development.

---

## ADR-08: Loki Standalone Chart Over loki-stack

**Status:** Accepted — after real incident

### Context

`grafana/loki-stack` was the standard Loki deployment chart for years. It is now deprecated and frozen on Loki v2.9.3.

Grafana 13.0.2 (deployed by `kube-prometheus-stack`) changed its Loki data source health check to use query syntax that Loki 2.9.3 doesn't support. The result: Grafana's data source test always reported `Unable to connect with Loki` even though Loki was running and accepting logs. Grafana 13 merged "Save" and "Save & test" into a single button — impossible to save without the test passing.

After migration, a secondary issue appeared: `mkdir /var/loki: read-only file system`. Loki 3.x needs to write to `/var/loki` but the container's security context had `readOnlyRootFilesystem: true`.

### Decision

Migrate to `grafana/loki` (Loki 3.6.7) with `grafana/promtail` as a separate installation. Set `securityContext.readOnlyRootFilesystem: false`.

### Consequences

**Benefits:** Compatible with Grafana 13. Health check passes. Log queries work.

**Trade-offs:** Promtail is now a separate chart and separate deploy step.

---

## ADR-09: ESO Webhook Disabled in Dev

**Status:** Accepted

### Context

ESO installs three components by default: controller, webhook (validates ExternalSecret manifests), and cert-controller (manages webhook TLS). The webhook and cert-controller consume 2 pod slots on a cluster with a hard 22-pod ceiling.

### Decision

Disable webhook and cert-controller in dev:

```yaml
--set webhook.create=false
--set certController.create=false
```

### Consequences

**Benefits:** Saves 2 pod slots. Promtail can schedule on both nodes.

**Trade-offs:** Malformed ExternalSecret manifests are accepted by Kubernetes without validation. Errors appear after apply rather than during. Acceptable in dev where sync status is checked after every apply.

---

## ADR-10: Dynamic ARN Resolution Over GitHub Secrets

**Status:** Accepted

### Context

Several ARNs were stored as GitHub Secrets: `ACM_CERT_ARN`, `LBC_IRSA_ROLE_ARN`, `ESO_IRSA_ROLE_ARN`. Every time the cluster was destroyed and recreated, ACM issued a new certificate with a new ARN, requiring a manual secret update before the next deploy would succeed. This was a recurring source of deploy failures after full cluster rebuilds.

### Decision

Fetch ARNs dynamically from AWS at workflow runtime. Since the workflow already has AWS credentials via OIDC, it can query ACM and IAM:

```bash
CERT_ARN=$(aws acm list-certificates \
  --certificate-statuses ISSUED \
  --query 'CertificateSummaryList[?DomainName==`therealblessing.com`].CertificateArn' \
  --output text)

LBC_ROLE=$(aws iam get-role \
  --role-name cloudops-dev-lbc-irsa-role \
  --query 'Role.Arn' \
  --output text)
```

### Consequences

**Benefits:** Deploy is fully self-contained after cluster rebuilds. Reduces GitHub Secrets from 8 to 5. Fails loudly if cert is not ISSUED rather than silently using a stale ARN.

**Trade-offs:** Workflow fails if the certificate hasn't been validated yet — correct failure mode.

---

## ADR-11: Trivy Container Scanning as Build Gateway

**Status:** Accepted

### Context

Two options for scanning: after push (ECR native scanning) or before push (Trivy as gateway). With ECR scanning, the image is already in ECR when findings appear — a deployment could pull a vulnerable image before anyone reviews results. With Trivy as gateway, nothing vulnerable ever reaches ECR.

`ignore-unfixed: true` skips vulnerabilities with no available fix — blocking deploys on unfixable CVEs only creates noise without any actionable path to resolution.

The pip vendored SBOM (`pip/_vendor/bom.cdx.json`) embeds old package versions that pip uses internally. These are pip-internal and never execute as standalone code. The vendor directory is excluded via `skip-dirs` to prevent false positives.

### Decision

Trivy scans the locally built image before push. CRITICAL or HIGH findings block the pipeline. Results upload to GitHub Security tab as SARIF.

```
Build image (local) → Trivy scan → Push to ECR (only if clean)
```

### Consequences

**Benefits:** No vulnerable image ever reaches ECR or the cluster. Findings visible in GitHub Security tab with history.

**Trade-offs:** Build time increases ~2-5 minutes. Requires `security-events: write` workflow permission.

---

## ADR-12: RDS Off-Hours via GitHub Actions Cron

**Status:** Accepted

### Context

Cloud Custodian's off-hours policy requires Lambda mode for true scheduled execution. In CLI mode it would need to run every hour via cron just to check if it should act — adding c7n dependency and Lambda infrastructure overhead.

The GitHub Actions role already has AWS credentials. Native AWS CLI can start and stop RDS directly.

### Decision

Use GitHub Actions cron workflows with AWS CLI rather than Cloud Custodian for RDS scheduling:

- `0 22 * * *` — stop at 10pm UTC daily
- `0 8 * * *` — start at 8am UTC daily

Step outputs (`steps.action.outputs.action`) are used for conditions rather than environment variables — environment variable conditionals in `if:` blocks have subtle GitHub Actions evaluation issues.

### Consequences

**Benefits:** No Lambda infrastructure. No Cloud Custodian dependency for scheduling. Simple, auditable workflow runs with full logs.

**Trade-offs:** GitHub Actions scheduled workflows on free tier can be delayed during peak usage. The workflow includes a ±1 hour buffer in the hour check to handle delays.