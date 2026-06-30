variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

# ============================================================
# EKS CLUSTER
# ============================================================
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

# ============================================================
# NETWORKING & SG
# ============================================================
variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker node placement"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security Group ID for the EKS Control Plane"
  type        = string
}

variable "node_sg_id" {
  description = "Security Group ID for EKS Worker Nodes"
  type        = string
}

# ============================================================
# IAM
# ============================================================
variable "cluster_role_arn" {
  description = "ARN of the IAM Role for the EKS Control Plane"
  type        = string
}

variable "node_group_role_arn" {
  description = "ARN of the IAM Role for the EKS Managed Node Group"
  type        = string
}

# ============================================================
# NODE GROUP
# ============================================================
variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "node_disk_size" {
  description = "EBS root volume size in GiB for each worker node"
  type        = number
}

# ============================================================
# CLUSTER ENDPOINT ACCESS
# ============================================================
variable "cluster_endpoint_public_access" {
  description = "Enable public access to the Kubernetes API server endpoint"
  type        = bool
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the Kubernetes API server endpoint within the VPC"
  type        = bool
}
