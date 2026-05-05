variable "vpc_name"           { type = string }
variable "igw_name"           { type = string }
variable "public_subnet_names"  { type = list(string) }
variable "private_subnet_names" { type = list(string) }
variable "nat_eip_name"       { type = string }
variable "nat_gw_name"        { type = string }
variable "public_rt_name"     { type = string }
variable "private_rt_name"    { type = string }

variable "vpc_cidr"           { type = string }
variable "azs"                { type = list(string) }
variable "public_subnets"     { type = list(string) }
variable "private_subnets"    { type = list(string) }
variable "enable_nat_gateway" { type = bool; default = true }
variable "single_nat_gateway" { type = bool; default = true }
variable "tags"               { type = map(string); default = {} }