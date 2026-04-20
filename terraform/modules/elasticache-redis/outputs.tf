output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}
output "redis_port" {
  value = aws_elasticache_cluster.redis.port
}
output "redis_secret_arn" {
  value = aws_secretsmanager_secret.redis_secret.arn
}