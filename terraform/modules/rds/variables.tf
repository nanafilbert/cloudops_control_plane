variable "identifier" {
  description = "RDS instance identifier"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  default     = "15.3"
}

variable "instance_class" {
  description = "RDS instance class"
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GB"
  default     = 20
}

variable "db_name" {
  description = "Database name"
}

variable "db_username" {
  description = "Master username"
}

variable "security_group_id" {
  description = "Security group ID for RDS"
}

variable "subnet_ids" {
  description = "List of subnet IDs for DB subnet group"
  type        = list(string)
}

variable "backup_retention_period" {
  description = "Days to retain backups"
  default     = 7
}

variable "backup_window" {
  description = "Backup window"
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Maintenance window"
  default     = "sun:04:00-sun:05:00"
}

variable "skip_final_snapshot" {
  default = true
}

variable "deletion_protection" {
  default = false
}

variable "secret_name" {
  description = "Name of AWS Secrets Manager secret"
}

variable "tags" {
  type    = map(string)
  default = {}
}