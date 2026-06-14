terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── VPC ─────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  vpc_name             = local.vpc_name
  igw_name             = local.igw_name
  nat_eip_name         = local.nat_eip_name
  nat_gw_name          = local.nat_gw_name
  public_rt_name       = local.public_rt_name
  private_rt_name      = local.private_rt_name
  public_subnet_names  = local.public_subnet_names
  private_subnet_names = local.private_subnet_names

  vpc_cidr           = "10.0.0.0/16"
  azs                = ["us-east-1a", "us-east-1b"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets    = ["10.0.1.0/24",   "10.0.2.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.common_tags
}

# ── Security Groups ───────────────────────────────────────────────
module "security" {
  source = "../../modules/security"


  eks_sg_name   = local.eks_sg_name
  rds_sg_name   = local.rds_sg_name
  redis_sg_name = local.redis_sg_name
  vpc_id        = module.vpc.vpc_id

  eks_cluster_security_group_id = module.eks.node_security_group_id

  tags = local.common_tags
}

# ── EKS ──────────────────────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  cluster_name      = local.eks_cluster_name
  cluster_role_name = local.eks_cluster_role
  node_role_name    = local.eks_node_role
  cluster_version   = "1.34"
  vpc_id            = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  admin_iam_principal_arn = var.admin_iam_principal_arn
  
  node_groups = {
    main = {
      name           = "${local.base}-eks-ng-main"
      desired_size   = 2
      min_size       = 1
      max_size       = 2
      instance_types = ["t4g.medium"]
      ami_type       = "AL2023_ARM_64_STANDARD"
    }
  }

  tags = local.common_tags
}

# ── RDS ──────────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  identifier        = local.rds_identifier
  subnet_grp_name   = local.rds_subnet_grp
  param_grp_name    = local.rds_param_grp
  secret_name       = local.rds_secret
  engine_version    = "16.3"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  db_name           = "game_db"
  db_username       = var.db_username
  security_group_id = module.security.rds_security_group_id
  subnet_ids        = module.vpc.private_subnet_ids
  backup_retention_period = 0

  tags = local.common_tags
}

# ── Redis ─────────────────────────────────────────────────────────
module "redis" {
  source = "../../modules/elasticache-redis"

  cluster_name      = local.redis_cluster
  subnet_grp_name   = local.redis_subnet_grp
  secret_name       = local.redis_secret
  node_type         = "cache.t4g.micro"
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security.redis_security_group_id

  tags = local.common_tags
}

# ── ECR ──────────────────────────────────────────────────────────
module "ecr_game" {
  source = "../../modules/ecr"

  repository_name = local.ecr_game_repo

  tags = local.common_tags
}

# ── IAM / IRSA ────────────────────────────────────────────────────
module "irsa_game" {
  source = "../../modules/iam-irsa"

  role_name                    = local.irsa_game_role
  policy_name                  = local.irsa_game_policy
  oidc_provider_arn            = module.eks.oidc_provider_arn
  namespace                    = "game"
  service_account              = "game-sa"
  attach_secretsmanager_policy = true

  tags = local.common_tags
}


module "irsa_eso" {
  source = "../../modules/iam-irsa"

  role_name                    = "${local.base}-eso-irsa-role"
  policy_name                  = "${local.base}-eso-secretsmanager-policy"
  oidc_provider_arn            = module.eks.oidc_provider_arn
  namespace                    = "external-secrets"
  service_account              = "external-secrets"
  attach_secretsmanager_policy = true

  tags = local.common_tags
}


module "irsa_lbc" {
  source = "../../modules/iam-irsa"

  role_name   = "${local.base}-lbc-irsa-role"
  policy_name = "${local.base}-lbc-policy"

  oidc_provider_arn            = module.eks.oidc_provider_arn
  namespace                    = "kube-system"
  service_account              = "aws-load-balancer-controller"
  attach_secretsmanager_policy = false

  tags = local.common_tags
}


resource "aws_iam_role_policy_attachment" "lbc" {
  role       = module.irsa_lbc.role_name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_iam_policy" "lbc" {
  name = "${local.base}-aws-load-balancer-controller-policy"

  policy = file("${path.module}/policies/lbc-policy.json")

  tags = local.common_tags
}

resource "aws_budgets_budget" "monthly" {
  name         = "${local.base}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "30"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}


resource "aws_acm_certificate" "game" {
  domain_name               = "therealblessing.com"
  subject_alternative_names = [
    "www.therealblessing.com",
    "*.therealblessing.com" 
  ]
  validation_method         = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.base}-acm-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

