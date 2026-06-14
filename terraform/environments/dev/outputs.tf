# ── VPC ──────────────────────────────────────────────────────────
output "vpc_id"             { value = module.vpc.vpc_id }
output "public_subnet_ids"  { value = module.vpc.public_subnet_ids }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }

# ── EKS ──────────────────────────────────────────────────────────
output "eks_cluster_name"     { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "eks_oidc_provider"    { value = module.eks.oidc_provider_arn }

# ── RDS ──────────────────────────────────────────────────────────
output "rds_endpoint"   { value = module.rds.db_endpoint }
output "rds_secret_arn" { value = module.rds.db_secret_arn }

# ── Redis ─────────────────────────────────────────────────────────
output "redis_endpoint"   { value = module.redis.redis_endpoint }
output "redis_secret_arn" { value = module.redis.redis_secret_arn }

# ── ECR ──────────────────────────────────────────────────────────
output "ecr_game_repo_url" { value = module.ecr_game.repository_url }

# ── IRSA ─────────────────────────────────────────────────────────
output "irsa_game_role_arn" { value = module.irsa_game.role_arn }
output "irsa_eso_role_arn"  { value = module.irsa_eso.role_arn }

# ── LBC IRSA ─────────────────────────────────────────────────────
output "lbc_irsa_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller — add to GitHub secret LBC_IRSA_ROLE_ARN"
  value       = module.irsa_lbc.role_arn  
}

# ── ACM ──────────────────────────────────────────────────────────
output "acm_certificate_arn" {
  description = "ACM certificate ARN — add to GitHub secret ACM_CERT_ARN"
  value       = aws_acm_certificate.game.arn
}

output "acm_validation_records" {
  description = "DNS validation records — add CNAMEs to Namecheap"
  value       = aws_acm_certificate.game.domain_validation_options
}