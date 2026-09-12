# Troubleshooting Guide

This document tells the real story of building cloudops_control_plane — every significant incident, its root cause, and how it was resolved. These are not hypothetical scenarios. Every issue happened during the actual build, in roughly the order they occurred.

---

## Incident 01: Community VPC Module — No Per-Resource Naming Control

**Symptom:** Resources in the AWS console had names like `cloudops-dev-vpc-private-us-east-1a`. Impossible to tell what each resource was for without clicking into it.

**Root cause:** `terraform-aws-modules/vpc` derives all sub-resource names from a single `name` input. You cannot give individual resources explicit names.

**Resolution:** Replaced with a custom VPC module accepting explicit name variables for every resource. All names defined in `locals.tf` derived from `"${local.project}-${local.env}"`.

---

## Incident 02: `single_nat_gateway` Variable Declared But Not Wired

**Symptom:** The variable existed in `variables.tf` but changing it had no effect. Resource count was hardcoded to `1`.

**Root cause:**
```hcl
# What was there (wrong):
resource "aws_nat_gateway" "this" {
  count = 1   # hardcoded — variable ignored
}
```

**Resolution:** Wired the variable into a `nat_count` local that controls actual resource creation.

**Lesson:** Declaring a variable doesn't make it do anything. It must be referenced in resource logic.

---

## Incident 03: `exec format error` — Architecture Mismatch

**Symptom:** Pods showed status `Running` then immediately crashed. Logs showed:
```
exec /usr/bin/sh: exec format error
```

**Root cause:** GitHub Actions runners are x86. `docker build` without a platform flag produces an x86 image. EKS nodes are ARM64 (t4g.small). The format incompatibility only surfaces at execution time — the image pulls successfully and the pod shows `Running` before crashing.

**Resolution:**
```yaml
- uses: docker/setup-qemu-action@v3
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    platforms: linux/arm64
    push: true
```

---

## Incident 04: t4g.small Pod Ceiling — `Too many pods`

**Symptom:** Pods stuck `Pending`. `kubectl describe pod` showed:
```
0/2 nodes are available: 2 Too many pods
```
CPU and memory had 50%+ headroom.

**Root cause:** EKS pod limits are determined by ENI IP allocation, not CPU/RAM. `t4g.small`: 3 ENIs × 4 IPs = 11 pods max per node. With 2 nodes: 22 pod ceiling. This was hit repeatedly as new components were added.

**Resolution:** Multiple interventions to reduce pod count:
- Disabled ESO webhook + cert-controller: -2 pods
- Disabled loki-canary: -2 pods
- Scaled AWS LBC to 1 replica: -1 pod

Attempted upgrade to `t4g.medium` — blocked by AWS Free Tier: `InvalidParameterCombination: The specified instance type is not eligible for Free Tier`.

**What to check:**
```bash
kubectl get pods -A --no-headers | wc -l
kubectl describe nodes | grep -A5 "Allocated resources"
```

---

## Incident 05: EKS Cluster Failed — `%!s(<nil>)`

**Symptom:**
```
Error: waiting for EKS Cluster create: unexpected state 'FAILED'
last error: %!s(<nil>)
```
No useful error in Terraform output.

**Root cause:** Terraform didn't capture the actual failure reason. The real error was visible via:
```bash
aws eks describe-cluster \
  --name cloudops-dev-eks-cluster \
  --region us-east-1 \
  --query 'cluster.statusReason'
```
IAM role trust policy hadn't fully propagated (IAM eventual consistency).

**Resolution:** Re-running `terraform apply` after a brief wait succeeded. For persistent failures:
```bash
terraform destroy -target=module.eks.aws_eks_cluster.this -auto-approve
terraform apply -target=module.eks -auto-approve
```

---

## Incident 06: WSL DNS — `no such host` for EKS Endpoint

**Symptom:**
```
dial tcp: lookup EF6C6EC07527ED1F6642983800C24144.gr7.us-east-1.eks.amazonaws.com
on 10.255.255.254:53: no such host
```

**Root cause:** WSL's default DNS server (`10.255.255.254`) is WSL's internal resolver and couldn't resolve the EKS endpoint. WSL regenerated `/etc/resolv.conf` on restart, overwriting any manual fix.

**Resolution:**
```bash
sudo bash -c 'cat > /etc/wsl.conf << EOF
[network]
generateResolvConf = false
EOF'

sudo rm /etc/resolv.conf
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo chattr +i /etc/resolv.conf
```
Then from PowerShell: `wsl --shutdown`

---

## Incident 07: Secrets Manager Secrets in PENDING_DELETION State

**Symptom:**
```
Error: creating Secrets Manager Secret: InvalidRequestException:
You can't create this secret because a secret with this name is
already scheduled for deletion.
```

**Root cause:** AWS Secrets Manager has a 7-30 day recovery window. After `terraform destroy`, secrets enter `PENDING_DELETION`. On the next `terraform apply`, Terraform tries to create secrets with the same name — the name is still "taken".

**Resolution:** Changed the workflow to check state before acting:
```bash
STATUS=$(aws secretsmanager describe-secret \
  --secret-id $secret \
  --query 'DeletedDate' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STATUS" != "None" ] && [ "$STATUS" != "NOT_FOUND" ]; then
  aws secretsmanager restore-secret --secret-id $secret
fi
```

---

## Incident 08: ExternalSecret Stuck in SecretSyncedError

**Symptom:** ESO showed `SecretSyncedError`:
```
could not get ClusterSecretStore "aws-secrets-manager": not found
```
Then: `ClusterSecretStore is not ready`
Then: `Secret does not exist`

**Root cause — three separate causes:**

1. **Wrong apiVersion:** Manifest used `external-secrets.io/v1beta1` but ESO v0.10+ promoted it to `v1`. Apply appeared to succeed but ESO couldn't reconcile it.

2. **kubectl discovery cache:** Even after fixing apiVersion, `kubectl apply` failed with `resource mapping not found`. Fixed by:
```bash
rm -rf ~/.kube/cache/discovery/
```

3. **ESO IRSA annotation empty:** Service account had `eks.amazonaws.com/role-arn: ""`. ESO called Secrets Manager without credentials.

**What to check:**
```bash
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get sa external-secrets -n external-secrets \
  -o jsonpath='{.metadata.annotations}'
kubectl annotate externalsecret game-redis-credentials \
  -n game-dev force-sync=$(date +%s) --overwrite
```

---

## Incident 09: Redis WebSocket Failure — Security Group Mismatch

**Symptom:** Game service started successfully, WebSocket connections opened but immediately closed. Game wouldn't advance after answering. Redis connection hung indefinitely from inside the pod.

**Root cause:** The Redis security group allowed port 6379 from `cloudops-dev-eks-sg` — our custom security group. But EKS creates its own cluster security group and attaches it to all nodes. The actual security group on nodes was the EKS cluster SG (`module.eks.node_security_group_id`), not the custom one. Traffic was silently dropped.

**Resolution:** Changed RDS and Redis security group ingress to reference the EKS cluster security group:
```hcl
resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = var.eks_cluster_security_group_id  # the real one
  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"
}
```

**Key lesson:** EKS creates its own cluster security group. Your custom SGs are additional. Pods use the EKS cluster SG for all traffic.

---

## Incident 10: Ingress-Nginx Admission Job Stuck Pending

**Symptom:** Every `helm upgrade --install ingress-nginx` failed:
```
Error: UPGRADE FAILED: pre-upgrade hooks failed: timed out waiting for the condition
```

**Root cause:** Helm's pre-upgrade hook creates a job that validates the webhook. On the first failure (pod capacity), Helm left the job `Pending`. On the next attempt, Helm waited for the old pending job to complete. It never did. Classic deadlock.

**Resolution:** Clean up before every Helm install:
```bash
kubectl delete jobs --all -n ingress-nginx 2>/dev/null || true
kubectl delete pods --field-selector=status.phase=Pending \
  -n ingress-nginx 2>/dev/null || true
sleep 10
```

---

## Incident 11: `400 Bad Request — The plain HTTP request was sent to HTTPS port`

**Symptom:** `curl https://game.therealblessing.com` returned a 400 from nginx.

**Root cause:** The NLB's port 443 listener was sending traffic to nginx's internal `https` container port (which nginx expects to be TLS-encrypted). nginx received plain HTTP (already decrypted by the NLB) on a port configured for TLS.

**Resolution:** Override the targetPort in the Helm values:
```yaml
controller.service.targetPorts.https=http
```

This maps external port 443 → nginx's HTTP container port instead of its HTTPS container port.

**Traffic flow after fix:**
```
Browser HTTPS → NLB (TLS terminated) → NodePort → Service port 443
→ maps to nginx container port "http" → nginx receives plain HTTP → routes normally
```

---

## Incident 12: Infinite Redirect Loop — `ERR_TOO_MANY_REDIRECTS`

**Symptom:** After enabling `force-ssl-redirect`, browser showed `ERR_TOO_MANY_REDIRECTS`. curl showed a 308 redirect to HTTPS... from HTTPS.

**Root cause:** NLB operates at Layer 4 and does not add `X-Forwarded-Proto`. nginx has no way to know the original request was HTTPS — every request appears as plain HTTP. With `force-ssl-redirect: "true"`, nginx always redirects. Browser follows the redirect, NLB decrypts, nginx sees plain HTTP again — infinite loop.

**Resolution:** Remove port 80 from the NLB entirely. No HTTP entry point exists to redirect. HSTS handles browser enforcement.

---

## Incident 13: LBC Service Account Had ACM Cert ARN Instead of IAM Role ARN

**Symptom:** LBC logs showed:
```json
{"error":"ValidationError: Request ARN is invalid"}
```
The service account annotation showed an ACM cert ARN instead of an IAM role ARN.

**Root cause:** GitHub Secret `LBC_IRSA_ROLE_ARN` had the wrong value — it contained the ACM certificate ARN. Both look like long AWS ARNs and the wrong one was copy-pasted when setting up secrets.

**Resolution:**
```bash
kubectl annotate sa aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/cloudops-dev-lbc-irsa-role \
  --overwrite
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
```

**Long-term fix:** Fetch ARNs dynamically from AWS at runtime rather than storing them as GitHub Secrets.

---

## Incident 14: Loki Health Check Failure in Grafana 13

**Symptom:** Adding Loki data source in Grafana 13 always showed `Unable to connect with Loki`. But from inside the Grafana pod: `wget -qO- http://loki.logging.svc.cluster.local:3100/ready` returned `ready`.

**Root cause:** `grafana/loki-stack` was frozen on Loki v2.9.3. Grafana 13 changed its health check to use query syntax Loki 2.9.3 doesn't support. Grafana 13 also merged "Save" and "Save & test" — impossible to save without the test passing.

**Resolution:** Migrated to `grafana/loki` (Loki 3.6.7). Also hit `mkdir /var/loki: read-only file system` — fixed with `securityContext.readOnlyRootFilesystem: false`.

---

## Incident 15: Namespace Stuck in Terminating During Destroy

**Symptom:** Destroy workflow hung. `kubectl get namespace game-dev` showed `Terminating` indefinitely.

**Root cause:** ExternalSecret resources have a finalizer (`externalsecrets.external-secrets.io/externalsecret-cleanup`). ESO processes this finalizer when an ExternalSecret is deleted. But the destroy workflow uninstalled ESO before deleting the namespace — nothing could process the finalizer. Classic deadlock.

**Resolution:** Remove ExternalSecret finalizers before deleting namespaces:
```bash
kubectl get externalsecret -n game-dev -o name | \
  xargs -I {} kubectl patch {} -n game-dev \
    --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
```

For namespaces still stuck:
```bash
kubectl get namespace game-dev -o json | \
  python3 -c "
import json, sys
ns = json.load(sys.stdin)
ns['spec']['finalizers'] = []
print(json.dumps(ns))
" | kubectl replace --raw "/api/v1/namespaces/game-dev/finalize" -f -
```

---

## Incident 16: Trivy Failing on pip Vendored SBOM

**Symptom:** Trivy found 2 HIGH vulnerabilities (`setuptools 70.3.0`, `msgpack 1.1.2`) even though `pip show setuptools msgpack` showed the upgraded versions (`84.0.0`, `1.2.1`).

**Root cause:** pip bundles its own vendored copies of packages inside `/usr/local/lib/python3.12/site-packages/pip/_vendor/bom.cdx.json`. This SBOM file embeds the old versions pip uses internally. Trivy reads this SBOM and flags the old versions even though your application uses the upgraded ones. The pip-vendored packages never run as standalone code in production.

**Resolution:** Exclude pip's vendor directory from the Trivy scan:
```yaml
skip-dirs: /usr/share/doc,/usr/local/lib/python3.12/site-packages/pip/_vendor
```

---

## Incident 17: GitHub OIDC Authentication Failure After Account Migration

**Symptom:**
```
Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Root cause:** AWS account was migrated from `234506497205` to `261175719079`. The GitHub Secret `GH_OIDC_ROLE_ARN` still contained the old account's role ARN. The OIDC provider and role existed in the new account but the secret pointed to the wrong account.

**Resolution:** Updated `GH_OIDC_ROLE_ARN` secret to:
```
arn:aws:iam::261175719079:role/github-actions-oidc-role
```

Also updated: `ADMIN_IAM_PRINCIPAL_ARN`, `backend.tf` S3 bucket, and all ECR repository URIs referencing the old account ID.

---

## Quick Reference Checks

```bash
# All pods and status
kubectl get pods -A

# Pod count vs ceiling
kubectl get pods -A --no-headers | wc -l   # ceiling: 22

# Why is a pod Pending?
kubectl describe pod <name> -n <namespace> | grep -A10 "Events"

# Why is a pod crashing?
kubectl logs <name> -n <namespace> --previous

# ExternalSecret sync status
kubectl get externalsecret -A
kubectl describe externalsecret game-redis-credentials -n game-dev

# LBC reconciliation errors
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20

# NLB listeners (confirm TLS configured)
LB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName,`cloudops-dev-nlb`)].LoadBalancerArn' \
  --output text)
aws elbv2 describe-listeners --load-balancer-arn $LB_ARN \
  --query 'Listeners[*].{Port:Port,Protocol:Protocol}'

# ACM certificate status
aws acm list-certificates \
  --certificate-statuses ISSUED \
  --query 'CertificateSummaryList[*].{Domain:DomainName,ARN:CertificateArn}'

# Redis connectivity from inside pod
kubectl exec -n game-dev \
  $(kubectl get pod -n game-dev -l app=game-service -o jsonpath='{.items[0].metadata.name}') \
  -- python3 -c "
import redis, os
r = redis.from_url(os.environ['REDIS_URL'])
print('Redis ping:', r.ping())
"

# RDS current status
aws rds describe-db-instances \
  --db-instance-identifier cloudops-dev-postgres-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
```