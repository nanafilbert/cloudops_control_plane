locals {
  project = "cloudops"
  env     = "dev"
  base    = "${local.project}-${local.env}"

  # VPC
  vpc_name             = "${local.base}-vpc"
  igw_name             = "${local.base}-igw"
  nat_eip_name         = "${local.base}-nat-eip"
  nat_gw_name          = "${local.base}-nat-gw"
  public_rt_name       = "${local.base}-public-rt"
  private_rt_name      = "${local.base}-private-rt"
  public_subnet_names  = ["${local.base}-public-subnet-1a", "${local.base}-public-subnet-1b"]
  private_subnet_names = ["${local.base}-private-subnet-1a", "${local.base}-private-subnet-1b"]

  # Security Groups
  eks_sg_name   = "${local.base}-eks-sg"
  rds_sg_name   = "${local.base}-rds-sg"
  redis_sg_name = "${local.base}-redis-sg"

  # EKS
  eks_cluster_name   = "${local.base}-eks"
  eks_cluster_role   = "${local.base}-eks-cluster-role"
  eks_node_role      = "${local.base}-eks-node-role"

  # RDS
  rds_identifier    = "${local.base}-postgres-db"
  rds_subnet_grp    = "${local.base}-rds-subnet-grp"
  rds_param_grp     = "${local.base}-postgres-param-grp"
  rds_secret        = "${local.base}-postgres-secret"

  # Redis
  redis_cluster     = "${local.base}-redis"
  redis_subnet_grp  = "${local.base}-redis-subnet-grp"
  redis_secret      = "${local.base}-redis-secret"

  # ECR
  ecr_game_repo     = "${local.project}/${local.env}/game-service"

  # IRSA
  irsa_game_role    = "${local.base}-game-irsa-role"
  irsa_game_policy  = "${local.base}-game-secretsmanager-policy"

  common_tags = {
    Environment = local.env
    Project     = "cloudops-control-plane"
    ManagedBy   = "Terraform"
  }
}