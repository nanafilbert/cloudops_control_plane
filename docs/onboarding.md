

## 📄 `docs/onboarding.md`

```markdown
# Engineer Onboarding

## Prerequisites
- AWS account with administrative access (for bootstrap only)
- Installed tools:
  - `aws-cli` (configured with credentials)
  - `terraform` >= 1.3
  - `kubectl` >= 1.28
  - `helm` >= 3.0
  - `python3` + `boto3` (for cost script)
  - `kubeseal` (optional, for sealed secrets)

## One‑Time Setup (per AWS account)

### 1. Bootstrap Backend (S3 + DynamoDB)
```bash
cd bootstrap/backend
terraform init
terraform apply -var="account_id=123456789012"
Copy the output state_bucket name.

2. Bootstrap IAM (GitHub OIDC Role)

cd ../iam
terraform init
terraform apply -var="github_repo=your-org/cloudops_control_plane"
Copy the output github_oidc_role_arn.

3. Add GitHub Secret
In your repository: Settings → Secrets and variables → Actions
Add secret GH_OIDC_ROLE_ARN with the ARN from step 2.

Deploy the Environment
4. Update Backend Reference
Edit terraform/env/dev/backend.tf and replace bucket with the name from step 1.

5. Apply Infrastructure

cd terraform/env/dev
terraform init
terraform apply -auto-approve
6. Configure kubectl

aws eks update-kubeconfig --name cloudops-dev --region us-east-1
7. Deploy Game Service

./scripts/deploy.sh
8. Verify

kubectl get pods -n game-dev
curl https://game.dev.yourdomain.com/health   # if ingress is configured
Access Monitoring
Grafana:


kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
URL: http://localhost:3000 (admin / prom-operator)

Loki logs:


kubectl logs -l app=game-service -n game-dev
Cleanup
To destroy everything:


cd terraform/env/dev
terraform destroy -auto-approve
Then delete the S3 bucket and DynamoDB table manually if no longer needed.