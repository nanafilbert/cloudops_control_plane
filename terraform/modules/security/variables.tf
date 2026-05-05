variable "eks_sg_name" {
 description = "Name of the EKS security group"
 type = string 
}

variable "rds_sg_name"   {
 description = "Name of the RDS security group"
 type = string
}

variable "redis_sg_name" {
 description = "Name of the Redis security group"
 type = string
}

variable "vpc_id"        {
 description = "ID of the VPC"
 type = string
}

variable "tags" {
  description = "Tags to apply to the repository"
  type        = map(string)
  default     = {}
}