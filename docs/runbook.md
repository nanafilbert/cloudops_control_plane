# Runbooks

## Runbook 001: High Error Rate (Game Service)

### Symptoms
- HTTP 5xx responses from `/game/score`
- Pods in `CrashLoopBackOff`
- Increased latency

### Diagnosis
1. **Check logs:**
   ```bash
   kubectl logs -l app=game-service -n game-dev --tail=50
Verify database connectivity:

bash
kubectl exec -it <pod-name> -n game-dev -- sh -c "nc -zv <db-host> 5432"
Check ExternalSecret sync status:

bash
kubectl get externalsecret -n game-dev
kubectl describe externalsecret game-db-secret -n game-dev
Resolution
If DB unreachable: check RDS security group (inbound from EKS nodes).

If secret missing: trigger ExternalSecret refresh by deleting the secret.

If code error: rollback deployment:

bash
kubectl rollout undo deployment/game-service -n game-dev
Runbook 002: Budget Threshold Exceeded
Symptoms
FinOps workflow fails with BUDGET EXCEEDED

Cost report shows total > $30

Diagnosis
Run cost report manually:

bash
python3 finops/automation/automation-cost-report.py
Identify expensive service (RDS, NAT Gateway, EKS control plane).

Resolution
Scale down game replicas:

bash
kubectl scale deployment game-service --replicas=1 -n game-dev
If RDS is idle, stop it (demo only):

bash
aws rds stop-db-instance --db-instance-identifier cloudops-game-db
If NAT Gateway is unnecessary, destroy it via Terraform.

Runbook 003: Pod Stuck in Pending
Diagnosis
bash
kubectl describe pod <pod-name> -n game-dev
Look for:

Insufficient CPU/memory → increase node group size.

Image pull error → check ECR permissions.

Resolution
Force deletion:

bash
kubectl delete pod <pod-name> -n game-dev
If node is unhealthy, cordon and drain:

bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data