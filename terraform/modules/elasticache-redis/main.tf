terraform {
  required_providers {
     aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }      

      random = {
        source  = "hashicorp/random"
        version = "~> 3.0"
      }
  }
}


resource "aws_elasticache_subnet_group" "this" {
  name       = var.subnet_grp_name
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = var.subnet_grp_name })
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.cluster_name
  description          = "${var.cluster_name} Redis cluster"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes
  auth_token           = random_password.redis.result
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [var.security_group_id]

  tags = merge(var.tags, { Name = var.cluster_name })
}

resource "aws_secretsmanager_secret" "redis" {
  name = var.secret_name
  tags = merge(var.tags, { Name = var.secret_name })
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    host     = aws_elasticache_replication_group.this.primary_endpoint_address
    port     = 6379
    password = random_password.redis.result
  })
}