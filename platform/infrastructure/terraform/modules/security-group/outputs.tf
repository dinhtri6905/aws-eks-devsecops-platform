# ============================================================
# EKS CONTROL PLANE
# ============================================================
output "eks_control_plane_sg_id" {
  description = "Security Group ID for the EKS Control Plane"
  value       = aws_security_group.eks_control_plane.id
}

# ============================================================
# EKS NODES
# ============================================================
output "eks_nodes_sg_id" {
  description = "Security Group ID for EKS Worker Nodes"
  value       = aws_security_group.eks_nodes.id
}

# ============================================================
# ALB
# ============================================================
output "alb_sg_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

# ============================================================
# RDS
# ============================================================
output "rds_sg_id" {
  description = "Security Group ID for the RDS PostgreSQL instance"
  value       = aws_security_group.rds.id
}
