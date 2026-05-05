variable "identifier"               { type = string }
variable "subnet_grp_name"          { type = string }
variable "param_grp_name"           { type = string }
variable "secret_name"              { type = string }
variable "engine_version"           { type = string }
variable "instance_class"           { type = string }
variable "allocated_storage"        { type = number }
variable "db_name"                  { type = string }
variable "db_username"              { type = string }
variable "security_group_id"        { type = string }
variable "subnet_ids"               { type = list(string) }
variable "backup_retention_period"  { type = number; default = 0 }
variable "tags"                     { type = map(string); default = {} }