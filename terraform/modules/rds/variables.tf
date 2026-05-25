variable "identifier" { 
description = "Unique identifier for the RDS instance (used in resource names and tags)"
type = string 
}
variable "subnet_grp_name"          { 
description = "Name for the DB subnet group"
type = string 
}
variable "param_grp_name"           { 
description = "Name for the DB parameter group"
type = string 
}
variable "secret_name"              { 
description = "Name for the DB secret in Secrets Manager"
type = string 
}
variable "engine_version"           { 
description = "Version of the database engine to use"
type = string 
}
variable "instance_class"           { 
description = "Class of the DB instance"
type = string 
}
variable "allocated_storage"    { 
description = "Amount of storage to allocate for the DB instance"
type = number 
}
variable "db_name" { 
description = "Name of the database"
type = string 
}

variable "db_username"              { 
description = "Username for the database user"
type = string 
}

variable "security_group_id"        { 
description = "ID of the security group for the DB instance"
type = string 
}
variable "subnet_ids"               { 
description = "List of subnet IDs for the DB instance"
type = list(string) 
}

variable "backup_retention_period" { 
description = "Number of days to retain backups. Set to 0 for no retention."
type = number
 default = 0 
}

variable "tags" {
  description = "Tags to apply to the repository"
  type        = map(string)
  default     = {}
}