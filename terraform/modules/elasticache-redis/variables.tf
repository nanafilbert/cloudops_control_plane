variable "cluster_name"    { type = string }
variable "subnet_grp_name" { type = string }
variable "secret_name"     { type = string }
variable "node_type"       { type = string }
variable "subnet_ids"      { type = list(string) }
variable "security_group_id" { type = string }
variable "num_cache_nodes" { type = number; default = 1 }
variable "tags"            { type = map(string); default = {} }