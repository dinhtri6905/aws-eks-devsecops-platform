# ============================================================
# GENERAL 
# ============================================================
variable "project_name" {
  description = "Project Name"
  type        = string
  default     = "eks-devsecops"
}

variable "environment" {
  description = "Deploy Environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}

# ============================================================
# VPC
# ============================================================
variable "vpc_cidr" {
  description = "CIDR block for the entire VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for Public Subnets (ALB, NAT Gateway)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnet CIDRs are required."
  }
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for Private Subnets (EKS Nodes, RDS)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "List of Availability Zones for subnet deployment (must match the number of subnet CIDRs)"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  = Use a single shared NAT Gateway (dev - cost optimized)
    false = One NAT Gateway per AZ (prod - high availability)
  EOT
  type        = bool
  default     = true # Change false to a NAT Gateway for per AZ
}

# ============================================================
# IAM
# ============================================================


# ============================================================
# SECURITY GROUP
# ============================================================


# ============================================================
# EKS
# ============================================================
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-devsecops-dev-eks-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "EBS root volume size in GiB per worker node"
  type        = number
  default     = 20
}

# ============================================================
# ECR
# ============================================================
variable "ecr_repository_names" {
  description = "List of ECR repository names to create for the Online Boutique microservices"
  type        = list(string)
  default = [
    "frontend",
    "cartservice",
    "productcatalogservice",
    "currencyservice",
    "paymentservice",
    "shippingservice",
    "emailservice",
    "checkoutservice",
    "recommendationservice",
    "adservice",
    "loadgenerator"
  ]
}

# ============================================================
# RDS
# ============================================================


# ============================================================
# ALB
# ============================================================