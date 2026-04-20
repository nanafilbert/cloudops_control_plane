output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "eks_workers_security_group_id" {
  value = aws_security_group.eks_workers.id
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}