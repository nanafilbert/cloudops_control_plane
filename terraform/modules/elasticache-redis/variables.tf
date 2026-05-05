variable "cluster_name" {
 description = "Name of the ElastiCache cluster"
 type = string 
}

variable "subnet_grp_name" { 
 description = "Name of the subnet group"
 type = string 
}

variable "secret_name"     { 
 description = "Name of the secret"
 type = string 
}

variable "node_type"       { 
 description = "Type of the cache node"
 type = string 
}

variable "subnet_ids"      { 
 description = "List of subnet IDs"
 type = list(string) 
}

variable "security_group_id" { 
 description = "ID of the security group"
 type = string 
}

    variable "num_cache_nodes" { 
  description = "Number of cache nodes"
  type = number
  default = 1
}

variable "tags" {
  description = "Tags to apply to the repository"
  type        = map(string)
  default     = {}
}