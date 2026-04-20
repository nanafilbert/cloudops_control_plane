resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name_prefix}-redis-subnet"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.security_group_id]

  tags = var.tags
}

# Store Redis endpoint in Secrets Manager
resource "aws_secretsmanager_secret" "redis_secret" {
  name = "${var.name_prefix}-redis"
}

resource "aws_secretsmanager_secret_version" "redis_secret_ver" {
  secret_id = aws_secretsmanager_secret.redis_secret.id
  secret_string = jsonencode({
    host = aws_elasticache_cluster.redis.cache_nodes[0].address
    port = aws_elasticache_cluster.redis.port
  })
}