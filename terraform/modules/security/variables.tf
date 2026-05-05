variable "eks_sg_name"   { type = string }
variable "rds_sg_name"   { type = string }
variable "redis_sg_name" { type = string }
variable "alb_sg_name"   { type = string }
variable "vpc_id"        { type = string }
variable "tags"          { type = map(string); default = {} }