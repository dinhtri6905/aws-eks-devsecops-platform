variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where all Security Groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC, used for internal traffic ingress rules"
  type        = string
}