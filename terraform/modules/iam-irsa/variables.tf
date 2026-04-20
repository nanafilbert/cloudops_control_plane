variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
}

variable "namespace" {
  description = "Kubernetes namespace"
}

variable "service_account" {
  description = "Kubernetes service account name"
}

variable "attach_secretsmanager_policy" {
  description = "Attach Secrets Manager read policy to the role"
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}