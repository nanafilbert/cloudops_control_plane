variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "github_oidc_role_arn" {
  description = "ARN of the GitHub OIDC role (from bootstrap)"
  type        = string
}