# Security groups
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group" "eks_workers" {
  name        = "${var.name_prefix}-eks-workers-sg"
  description = "Additional rules for EKS worker nodes"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

# KMS key for encryption
resource "aws_kms_key" "main" {
  description             = "${var.name_prefix}-kms-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}-key"
  target_key_id = aws_kms_key.main.key_id
}

# Security group rules (example: allow RDS from EKS workers)
resource "aws_security_group_rule" "rds_ingress_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.eks_worker_security_group_id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis-sg"
  description = "Security group for Redis"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "redis_ingress_eks" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = var.eks_worker_security_group_id
  security_group_id        = aws_security_group.redis.id
}