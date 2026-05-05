output "db_endpoint" {
 description = "Endpoint of the RDS instance"
 value = aws_db_instance.this.address 
}
output "db_secret_arn" {
 description = "ARN of the DB secret in Secrets Manager"
 value = aws_secretsmanager_secret.db.arn
}
output "db_port"       {
 description = "Port of the RDS instance"
 value = aws_db_instance.this.port
}