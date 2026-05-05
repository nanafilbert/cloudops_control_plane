locals {
  # ── Base identifiers ────────────────────────────────────────
  project = "cloudops"
  env     = "dev"
  base    = "${local.project}-${local.env}"

  # ── VPC / Networking ────────────────────────────────────────
  vpc_name             = "${local.base}-vpc"
  public_subnet_name   = "${local.base}-public-subnet"
  private_subnet_name  = "${local.base}-private-subnet"
  nat_eip_name         = "${local.base}-nat-eip"
  nat_gw_name          = "${local.base}-nat-gw"
  igw_name             = "${local.base}-igw"
  public_rt_name       = "${local.base}-public-rt"
  private_rt_name      = "${local.base}-private-rt"

  # ── Security Groups ──────────────────────────────────────────
  eks_sg_name     = "${local.base}-eks-sg"
  rds_sg_name     = "${local.base}-rds-sg"
  redis_sg_name   = "${local.base}-redis-sg"

  # ── EKS ─────────────────────────────────────────────────────
  eks_cluster_name     = "${local.base}-eks"
  eks_node_group_name  = "${local.base}-eks-ng-main"

  # ── Load Balancer ────────────────────────────────────────────
  alb_name         = "${local.base}-alb"
  alb_tg_name      = "${local.base}-alb-tg"

  # ── RDS ─────────────────────────────────────────────────────
  rds_identifier       = "${local.base}-postgres-db"    # e.g. cloudops-dev-postgres-db
  rds_subnet_grp_name  = "${local.base}-rds-subnet-grp"
  rds_secret_name      = "${local.base}-postgres-secret"

  # ── Redis ────────────────────────────────────────────────────
  redis_cluster_name   = "${local.base}-redis"
  redis_subnet_grp     = "${local.base}-redis-subnet-grp"
  redis_secret_name    = "${local.base}-redis-secret"

  # ── ECR ─────────────────────────────────────────────────────
  ecr_game_repo        = "${local.project}/${local.env}/game-service"  # cloudops/dev/game-service

  # ── IAM / IRSA ───────────────────────────────────────────────
  irsa_game_role_name  = "${local.base}-game-irsa-role"
  irsa_game_sa_name    = "game-sa"

  # ── Shared tags ──────────────────────────────────────────────
  common_tags = {
    Environment = local.env
    Project     = "cloudops-control-plane"
    ManagedBy   = "Terraform"
  }
}