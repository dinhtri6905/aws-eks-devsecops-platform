variable "project_name" {
  description = "Project name passed from the environment. Example: eks-devsecops"
  type        = string
}

variable "environment" {
  description = "Deployment environment passed from the environment. Example: dev | prod"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the entire VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for Public Subnets (ALB, NAT Gateway)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for Private Subnets (EKS Nodes, RDS)"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of Availability Zones for subnet deployment (must match the number of subnet CIDRs)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  = Use a single shared NAT Gateway (dev - cost optimized)
    false = One NAT Gateway per AZ (prod - high availability)
  EOT
  type    = bool
}