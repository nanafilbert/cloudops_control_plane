# Runbook

Day-2 operational procedures for cloudops_control_plane. Everything you need to operate the platform after it is deployed.

---

## Cluster Access

### Update kubeconfig after cluster recreate

Every cluster rebuild changes the API server endpoint:

```bash
aws eks update-kubeconfig \
  --name cloudops-dev-eks-cluster \
  --region us-east-1

kubectl get nodes
kubectl get pods -A
```

### Confirm everything is healthy after a fresh deploy

```bash
# All pods Running, none Pending or CrashLoopBackOff
kubectl get pods -A

# Game is accessible
curl -I https://game.therealblessing.com

# Redis secret synced
kubectl get externalsecret game-redis-credentials -n game-dev
# READY column should show True

# Ingress routing correctly
kubectl get ingress -n game-dev
# ADDRESS column should show the NLB hostname
```

---

## DNS Update After Cluster Recreate

Every rebuild creates a new NLB with a new hostname. Update Namecheap after every rebuild:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Namecheap → Advanced DNS → update CNAME record:

| Type | Host | Value |
|---|---|---|
| CNAME | `game` | `<new-nlb-hostname>` |

Verify propagation (allow 5-30 minutes):
```bash
nslookup game.therealblessing.com
curl -I https://game.therealblessing.com
```

---

## Grafana Access

Grafana is not exposed externally. Access via port-forward:

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# http://localhost:3000  admin / prom-operator
```

### Add data sources after fresh deploy

Grafana data is not persisted. After every cluster rebuild:

**Prometheus:**
1. Connections → Data sources → Add new → Prometheus
2. URL: `http://prometheus-monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090`
3. Save & test

**Loki:**
1. Connections → Data sources → Add new → Loki
2. URL: `http://loki.logging.svc.cluster.local:3100`
3. Save & test

### View game-service logs in Loki

1. Explore → select Loki data source
2. Query: `{namespace="game-dev"}`
3. Set time range to last 15 minutes

---

## Checking Resource Health

### Game service

```bash
kubectl get pods -n game-dev
kubectl logs -f -l app=game-service -n game-dev
kubectl logs -l app=game-service -n game-dev --previous  # crash logs
kubectl top pod -n game-dev
kubectl get hpa -n game-dev
```

### Redis connectivity

```bash
kubectl exec -n game-dev \
  $(kubectl get pod -n game-dev -l app=game-service -o jsonpath='{.items[0].metadata.name}') \
  -- python3 -c "
import redis, os
r = redis.from_url(os.environ['REDIS_URL'])
print('Redis ping:', r.ping())
print('Redis version:', r.info('server')['redis_version'])
"
```

### NLB and ingress

```bash
kubectl describe ingress game-service -n game-dev

LB_ARN=$(aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName,`cloudops-dev-nlb`)].LoadBalancerArn' \
  --output text)

aws elbv2 describe-listeners \
  --load-balancer-arn $LB_ARN \
  --region us-east-1 \
  --query 'Listeners[*].{Port:Port,Protocol:Protocol,Certs:Certificates[0].CertificateArn}'
```

### AWS Load Balancer Controller

```bash
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  --tail=30 | grep -v '"level":"info"'
```

### External Secrets Operator

```bash
kubectl get externalsecret -A
kubectl describe externalsecret game-redis-credentials -n game-dev

# Force re-sync
kubectl annotate externalsecret game-redis-credentials \
  -n game-dev \
  force-sync=$(date +%s) --overwrite

kubectl logs -n external-secrets \
  -l app.kubernetes.io/name=external-secrets --tail=30
```

---

## RDS Operations

### Check current status

```bash
aws rds describe-db-instances \
  --db-instance-identifier cloudops-dev-postgres-db \
  --region us-east-1 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}' \
  --output table
```

### Manual stop / start

```bash
# Stop RDS
aws rds stop-db-instance \
  --db-instance-identifier cloudops-dev-postgres-db \
  --region us-east-1

# Start RDS
aws rds start-db-instance \
  --db-instance-identifier cloudops-dev-postgres-db \
  --region us-east-1
```

### Trigger RDS schedule manually

```
GitHub → Actions → RDS Off-Hours Schedule → Run workflow → select stop or start
```

---

## Cost Checking

### Current month spend

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[*].{Service:Keys[0],Cost:Metrics.UnblendedCost.Amount}' \
  --output table | sort -k3 -rn
```

### Budget status

```bash
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --query 'Budgets[*].{Name:BudgetName,Limit:BudgetLimit.Amount,Actual:CalculatedSpend.ActualSpend.Amount}' \
  --output table
```

### Run FinOps report manually

```
GitHub → Actions → FinOps Reporter → Run workflow
```

Report is committed to `finops/reports/monthly.md` and uploaded as a workflow artifact.

---

## Terraform Operations

### Target a specific module

```bash
cd terraform/environments/dev

terraform apply -target=module.redis
terraform apply -target=module.eks
terraform apply -target=module.security
```

### Check state for a specific resource

```bash
terraform state list | grep redis
terraform state show module.redis.aws_elasticache_replication_group.this
```

### Import an existing resource

```bash
terraform import module.eks.aws_eks_cluster.this cloudops-dev-eks-cluster
```

---

## Deploy a New Application Version

Application updates trigger automatically when `services/game-service/**` changes. To manually redeploy without a code change:

```bash
helm upgrade game-service ./helm/game-service \
  --namespace game-dev \
  --values configs/dev/values-game-service.yaml \
  --reuse-values \
  --atomic \
  --timeout 5m
```

### Roll back to a previous Helm release

```bash
helm history game-service -n game-dev
helm rollback game-service -n game-dev          # previous revision
helm rollback game-service 3 -n game-dev        # specific revision
```

---

## Database Operations

### Run migrations manually

```bash
kubectl exec -it -n game-dev \
  $(kubectl get pod -n game-dev -l app=game-service -o jsonpath='{.items[0].metadata.name}') \
  -- python manage.py migrate
```

### Re-seed questions

```bash
POD=$(kubectl get pod -n game-dev -l app=game-service -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it -n game-dev $POD -- python manage.py seed_questions
kubectl exec -it -n game-dev $POD -- python manage.py seed_more_questions
```

---

## Secret Management

### Check secret values in Secrets Manager

```bash
aws secretsmanager get-secret-value \
  --secret-id cloudops-dev-redis-secret \
  --region us-east-1 \
  --query SecretString \
  --output text | python3 -m json.tool
```

### Check what's in the Kubernetes secret

```bash
kubectl get secret game-redis-credentials -n game-dev \
  -o jsonpath='{.data.REDIS_URL}' | base64 -d
```

### Restore a secret from pending deletion

```bash
aws secretsmanager restore-secret \
  --secret-id cloudops-dev-redis-secret \
  --region us-east-1
```

---

## Full Destroy and Rebuild

### Step 1 — Trigger destroy

```
GitHub → Actions → Destroy Environment → Run workflow
Type: DESTROY
Environment: dev
```

### Step 2 — Trigger rebuild

Push any commit to `main`. The full pipeline runs automatically.

### Step 3 — Update DNS

Get the new NLB hostname and update the CNAME in Namecheap.

### Step 4 — Verify

```bash
curl -I https://game.therealblessing.com
kubectl get pods -A
```

---

## SSL/TLS Checks

```bash
# Check certificate served
echo | openssl s_client -connect game.therealblessing.com:443 \
  -servername game.therealblessing.com 2>/dev/null \
  | openssl x509 -noout -dates -subject

# Verify HSTS header
curl -sI https://game.therealblessing.com | grep -i strict
# Should show: strict-transport-security: max-age=31536000

# ACM certificate status
aws acm describe-certificate \
  --certificate-arn $(terraform -chdir=terraform/environments/dev output -raw acm_certificate_arn) \
  --region us-east-1 \
  --query 'Certificate.{Status:Status,Expiry:NotAfter}'
```

---

## Incident Response Checklist

When something is broken, check in this order:

1. `kubectl get pods -n game-dev` — is the pod running?
2. `kubectl logs -l app=game-service -n game-dev --tail=50` — what do the logs say?
3. `kubectl get externalsecret game-redis-credentials -n game-dev` — is the secret synced?
4. Run Redis ping test from inside the pod
5. `kubectl get ingress -n game-dev` — is the ingress routing?
6. `kubectl get svc ingress-nginx-controller -n ingress-nginx` — does the NLB have an IP?
7. `nslookup game.therealblessing.com` — is DNS resolving?
8. `curl -I https://game.therealblessing.com` — is the cert valid?
9. `kubectl get events -n game-dev --sort-by='.lastTimestamp'` — any events?
10. Check LBC and ESO logs for AWS-level errors