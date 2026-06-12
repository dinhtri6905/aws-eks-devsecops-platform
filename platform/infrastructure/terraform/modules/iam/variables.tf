variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used in IAM role naming"
  type        = string
}
