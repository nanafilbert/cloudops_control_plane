# ── VPC ──────────────────────────────────────────────────────────
output "vpc_id"             { value = module.vpc.vpc_id }
output "public_subnet_ids"  { value = module.vpc.public_subnet_ids }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }

# ── EKS ──────────────────────────────────────────────────────────
output "eks_cluster_name"    { value = module.eks.cluster_name }
output "eks_cluster_endpoint"{ value = module.eks.cluster_endpoint }
output "eks_oidc_provider"   { value = module.eks.oidc_provider_arn }

# ── RDS ──────────────────────────────────────────────────────────
output "rds_endpoint"        { value = module.rds.db_endpoint }
output "rds_secret_arn"      { value = module.rds.db_secret_arn }

# ── Redis ─────────────────────────────────────────────────────────
output "redis_endpoint"      { value = module.redis.redis_endpoint }
output "redis_secret_arn"    { value = module.redis.redis_secret_arn }

# ── ECR ──────────────────────────────────────────────────────────
output "ecr_game_repo_url"   { value = module.ecr_game.repository_url }

# ── IRSA ─────────────────────────────────────────────────────────
output "irsa_game_role_arn"  { value = module.irsa_game.role_arn }
