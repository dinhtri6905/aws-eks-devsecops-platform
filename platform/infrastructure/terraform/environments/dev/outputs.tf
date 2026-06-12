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
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — used to create IRSA roles for platform tools"
  value       = module.eks.oidc_provider_arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  value       = module.eks.oidc_issuer_url
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the IRSA role for the EBS CSI Driver"
  value       = module.eks.ebs_csi_driver_role_arn
}

output "kubeconfig_command" {
  description = "AWS CLI command to update local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ============================================================
# ECR
# ============================================================
output "ecr_repository_urls" {
  description = "Map of microservice name to ECR repository URL"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of microservice name to ECR repository ARN"
  value       = module.ecr.repository_arns
}

output "ecr_registry_id" {
  description = "AWS account ID of the ECR registry"
  value       = module.ecr.registry_id
}


# ============================================================
# RDS
# ============================================================
output "db_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "db_instance_endpoint" {
  description = "RDS connection endpoint in host:port format"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "db_instance_address" {
  description = "RDS hostname — used in application connection strings"
  value       = module.rds.db_instance_address
  sensitive   = true
}

output "db_instance_port" {
  description = "RDS port"
  value       = module.rds.db_instance_port
}

output "db_name" {
  description = "Name of the initial database"
  value       = module.rds.db_name
}


# ============================================================
# ALB — LBC IRSA
# Use lbc_role_arn in the LBC Helm values:
#   serviceAccount.annotations."eks.amazonaws.com/role-arn"
# ============================================================
output "lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller — pass to Helm chart values"
  value       = module.alb.lbc_role_arn
}

output "lbc_policy_arn" {
  description = "ARN of the IAM policy attached to the LBC IRSA role"
  value       = module.alb.lbc_policy_arn
}



