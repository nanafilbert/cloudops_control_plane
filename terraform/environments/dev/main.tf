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

module "vpc" {
  source = "../../modules/vpc"

  vpc_name = "cloudops-dev"
  vpc_cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = "cloudops-dev"
  cluster_version     = "1.31"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids

  node_groups = {
    main = {
      desired_size = 1
      min_size     = 1
      max_size     = 2
      instance_types = ["t3.medium"]
    }
  }

  tags = local.common_tags
}

module "security" {
  source = "../../modules/security"

  name_prefix                    = "cloudops-dev"
  vpc_id                         = module.vpc.vpc_id
  eks_worker_security_group_id   = module.eks.node_security_group_id

  tags = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  identifier        = "cloudops-game-db"
  engine_version    = "15.3"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  db_name           = "game_db"
  db_username       = var.db_username
  security_group_id = module.security.rds_security_group_id
  subnet_ids        = module.vpc.private_subnet_ids
  secret_name       = "cloudops/game-db"
  backup_retention_period = 0 

  tags = local.common_tags
}

module "redis" {
  source = "../../modules/elasticache-redis"

  name_prefix       = "cloudops-dev"
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security.redis_security_group_id
  node_type         = "cache.t4g.micro"

  tags = local.common_tags
}

module "irsa_game" {
  source = "../../modules/iam-irsa"

  oidc_provider_arn              = module.eks.oidc_provider_arn
  namespace                      = "game"
  service_account                = "game-sa"
  attach_secretsmanager_policy   = true

  tags = local.common_tags
}

locals {
  common_tags = {
    Environment = "dev"
    Project     = "cloudops-control-plane"
    ManagedBy   = "Terraform"
  }
}