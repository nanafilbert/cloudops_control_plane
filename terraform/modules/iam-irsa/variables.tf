variable "role_name" {
 description = "Name of the IAM role to create"
 type = string
}

variable "policy_name" { 
  description = "Name of the IAM policy to create"
  type = string
}

variable "oidc_provider_arn" { 
  description = "ARN of the OIDC provider"
  type = string
}

variable "namespace"                   { 
  description = "Namespace for the service account"
  type = string
}

variable "service_account"             { 
  description = "Name of the service account"
  type = string
}

variable "attach_secretsmanager_policy" {
  description = "Enable the secrets manager policy"
  type = bool
  default = false
}

variable "tags" {
  description = "Tags to apply to the repository"
  type        = map(string)
  default     = {}
}