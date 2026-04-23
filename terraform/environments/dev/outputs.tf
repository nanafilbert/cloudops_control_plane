output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "db_secret_arn" {
  value = module.rds.db_secret_arn
}

output "irsa_role_arn" {
  value = module.irsa_game.irsa_role_arn
}