variable "role_name"                   { type = string }
variable "policy_name"                 { type = string }
variable "oidc_provider_arn"           { type = string }
variable "namespace"                   { type = string }
variable "service_account"             { type = string }
variable "attach_secretsmanager_policy" { type = bool; default = false }
variable "tags"                        { type = map(string); default = {} }