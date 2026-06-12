# ============================================================
# EKS CLUSTER
# ============================================================
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL of the Kubernetes API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group (auto-created by EKS)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# ============================================================
# NODE GROUP
# ============================================================
output "node_group_arn" {
  description = "ARN of the EKS managed node group"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "Current status of the EKS managed node group"
  value       = aws_eks_node_group.main.status
}

# ============================================================
# OIDC PROVIDER
# Consumed by: ALB module, future IRSA roles (ArgoCD, Falco, etc.)
# ============================================================
output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — used for IRSA role trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (includes https://)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ============================================================
# EBS CSI DRIVER
# ============================================================
output "ebs_csi_driver_role_arn" {
  description = "ARN of the IRSA role for the EBS CSI Driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}
