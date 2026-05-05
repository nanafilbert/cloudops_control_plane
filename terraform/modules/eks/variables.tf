variable "cluster_name"        { type = string }
variable "cluster_role_name"   { type = string }
variable "node_role_name"      { type = string }
variable "cluster_version"     { type = string }
variable "vpc_id"              { type = string }
variable "private_subnet_ids"  { type = list(string) }
variable "tags"                { type = map(string); default = {} }

variable "node_groups" {
  type = map(object({
    name           = string        # explicit name per group
    desired_size   = number
    min_size       = number
    max_size       = number
    instance_types = list(string)
    ami_type       = string
  }))
}