# ============================================================
# VPC
# ============================================================
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of Private Subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IPs attached to NAT Gateways"
  value       = module.vpc.nat_gateway_public_ips
}

# ============================================================
# IAM
# ============================================================
output "eks_cluster_role_arn" {
  description = "ARN of the EKS Cluster IAM Role"
  value       = module.iam.eks_cluster_role_arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS Cluster IAM Role"
  value       = module.iam.eks_cluster_role_name
}

output "eks_node_group_role_arn" {
  description = "ARN of the EKS Node Group IAM Role"
  value       = module.iam.eks_node_group_role_arn
}

output "eks_node_group_role_name" {
  description = "Name of the EKS Node Group IAM Role"
  value       = module.iam.eks_node_group_role_name
}

# ============================================================
# SECURITY GROUP
# ============================================================
output "eks_control_plane_sg_id" {
  description = "Security Group ID for the EKS Control Plane"
  value       = module.security-group.eks_control_plane_sg_id
}

output "eks_nodes_sg_id" {
  description = "Security Group ID for EKS Worker Nodes"
  value       = module.security-group.eks_nodes_sg_id
}

output "alb_sg_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = module.security-group.alb_sg_id
}

output "rds_sg_id" {
  description = "Security Group ID for the RDS PostgreSQL instance"
  value       = module.security-group.rds_sg_id
}

# ============================================================
# EKS
# ============================================================


# ============================================================
# ECR
# ============================================================


# ============================================================
# RDS
# ============================================================


# ============================================================
# ALB
# ============================================================



