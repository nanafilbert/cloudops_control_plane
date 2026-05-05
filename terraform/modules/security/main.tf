

# ── EKS ───────────────────────────────────────────────────────────
resource "aws_security_group" "eks" {
  name   = var.eks_sg_name
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = var.eks_sg_name })
}


resource "aws_vpc_security_group_egress_rule" "eks_out" {
  security_group_id = aws_security_group.eks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ── RDS ───────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name   = var.rds_sg_name
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = var.rds_sg_name })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ── Redis ─────────────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name   = var.redis_sg_name
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = var.redis_sg_name })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.eks.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}