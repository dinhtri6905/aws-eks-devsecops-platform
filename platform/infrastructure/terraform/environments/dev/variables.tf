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
  default     = "eks-devsecops-dev-cluster"
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
  default     = 3
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

variable "image_tag_mutability" {
  description = "Image tag mutability: MUTABLE allows overwriting tags, IMMUTABLE prevents it"
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  description = "Enable automatic vulnerability scanning when an image is pushed"
  type        = bool
  default     = true
}

variable "tagged_image_keep_count" {
  description = "Number of tagged images to retain per repository"
  type        = number
  default     = 10
}

variable "untagged_image_expiry_days" {
  description = "Number of days before untagged images are automatically removed"
  type        = number
  default     = 7
}


# ============================================================
# RDS
# ============================================================
variable "db_identifier" {
  description = "Unique identifier for the RDS instance"
  type        = string
  default     = "eks-devsecops-dev-postgres"
}

variable "db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "microservices_db"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "dbadmin"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage autoscaling ceiling in GiB"
  type        = number
  default     = 100
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.14"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment (false for dev, true for prod)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}


# ============================================================
# ALB
# ============================================================


# ============================================================
# ARGOCD + GITOPS
# ============================================================
variable "argocd_project_name" {
  description = "Name of the ArgoCD Project used to group and manage applications"
  type        = string
  default     = "platform-project"

  validation {
    condition     = length(trim(var.argocd_project_name, " ")) > 0
    error_message = "argocd_project_name cannot be empty."
  }
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version to deploy"
  type        = string
  default     = "7.6.8"
}

variable "argocd_server_insecure" {
  description = "Run ArgoCD in insecure mode (true when ALB terminates TLS)"
  type        = bool
  default     = true
}

variable "argocd_ha_enabled" {
  description = "Enable ArgoCD High Availability (multiple replicas) — false for dev"
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "URL of the GitOps repository ArgoCD will watch"
  type        = string
  default     = "https://github.com/dinhtri6905/aws-eks-devsecops-platform"
}

variable "gitops_repo_branch" {
  description = "Git branch for the Root Application to track"
  type        = string
  default     = "main"
}

variable "gitops_root_app_path" {
  description = "Path inside the repo that contains child Application manifests"
  type        = string
  default     = "platform/gitops/argocd/apps"
}

variable "gitops_repo_ssh_private_key" {
  description = "SSH private key for a private Git repo — set via TF_VAR_gitops_repo_ssh_private_key"
  type        = string
  default     = ""
  sensitive   = true
}
