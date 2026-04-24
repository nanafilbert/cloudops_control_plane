variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "node_groups" {
  description = "EKS managed node groups configuration"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags for resources"
  type        = map(string)
  default     = {}
}

