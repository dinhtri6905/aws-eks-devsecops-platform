# ============================================================
# EKS CLUSTER ROLE
# ============================================================
output "eks_cluster_role_arn" {
  description = "ARN of the EKS Cluster IAM Role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS Cluster IAM Role"
  value       = aws_iam_role.eks_cluster.name
}

# ============================================================
# EKS NODE GROUP ROLE
# ============================================================
output "eks_node_group_role_arn" {
  description = "ARN of the EKS Node Group IAM Role"
  value       = aws_iam_role.eks_node_group.arn
}

output "eks_node_group_role_name" {
  description = "Name of the EKS Node Group IAM Role"
  value       = aws_iam_role.eks_node_group.name
}
