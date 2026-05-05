variable "vpc_name" {
 description = "Name of the VPC"
 type = string
}

variable "igw_name" { 
 description = "Name of the Internet Gateway"
 type = string 
}

variable "public_subnet_names" { 
 description = "Names of the public subnets"
 type = list(string)
}

variable "private_subnet_names" { 
 description = "Names of the private subnets"
 type = list(string)
}

variable "nat_eip_name" { 
 description = "Name of the NAT EIP"
 type = string 
}

variable "nat_gw_name" { 
 description = "Name of the NAT Gateway"
 type = string 
}

variable "public_rt_name" { 
 description = "Name of the public route table"
 type = string 
}

variable "private_rt_name"    { description = "Name of the private route table"; type = string }

variable "vpc_cidr" { 
 description = "CIDR block for the VPC"
 type = string 
}

variable "azs" { 
 description = "List of Availability Zones"
 type = list(string) 
}

variable "public_subnets" { 
 description = "List of public subnet CIDRs"
 type = list(string) 
}

variable "private_subnets" { 
 description = "List of private subnet CIDRs"
  type = list(string) 
}

variable "enable_nat_gateway" { 
   description = "Should be true if you want to provision a NAT Gateway for your private subnets"
   type = bool
  default = true
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway for the public subnets"
  type = bool
  default = true
}

variable "tags" {
  description = "Tags to apply to the repository"
  type        = map(string)
  default     = {}
}