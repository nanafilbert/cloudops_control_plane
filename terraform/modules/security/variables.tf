variable "name_prefix" {
  description = "Prefix for resource names"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "eks_worker_security_group_id" {
  description = "EKS worker node security group ID (for ingress rules)"
}

variable "tags" {
  type    = map(string)
  default = {}
}