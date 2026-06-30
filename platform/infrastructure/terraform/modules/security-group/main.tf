locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ============================================================
# EKS CONTROL PLANE SECURITY GROUP
# ============================================================
resource "aws_security_group" "eks_control_plane" {
  #checkov:skip=CKV2_AWS_5:Security Group is attached by dependent Terraform resources in other modules.

  name        = "${local.name_prefix}-eks-control-plane-sg"
  description = "Security Group for EKS Control Plane - manages access to the Kubernetes API Server"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-eks-control-plane-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "control_plane_ingress_nodes_https" {
  security_group_id        = aws_security_group.eks_control_plane.id
  type                     = "ingress"
  description              = "Allow worker nodes to reach the Kubernetes API Server (HTTPS)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "control_plane_egress_all" {
  #checkov:skip=CKV_AWS_382:EKS control plane requires unrestricted outbound connectivity to AWS managed services.

  security_group_id = aws_security_group.eks_control_plane.id
  type              = "egress"
  description       = "Allow all outbound traffic from EKS Control Plane"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ============================================================
# EKS NODES SECURITY GROUP
# ============================================================
resource "aws_security_group" "eks_nodes" {
  #checkov:skip=CKV2_AWS_5:Security Group is attached by dependent Terraform resources in other modules.

  name        = "${local.name_prefix}-eks-nodes-sg"
  description = "Security Group for EKS Managed Worker Nodes - controls intra-node and API communication"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-eks-nodes-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "nodes_ingress_self" {
  security_group_id = aws_security_group.eks_nodes.id
  type              = "ingress"
  description       = "Allow all intra-node traffic for pod-to-pod and node-to-node communication"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
}

resource "aws_security_group_rule" "nodes_ingress_control_plane_ephemeral" {
  security_group_id        = aws_security_group.eks_nodes.id
  type                     = "ingress"
  description              = "Allow EKS Control Plane to communicate with worker nodes on ephemeral ports"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_control_plane.id
}

resource "aws_security_group_rule" "nodes_ingress_control_plane_kubelet" {
  security_group_id        = aws_security_group.eks_nodes.id
  type                     = "ingress"
  description              = "Allow EKS Control Plane to reach kubelet API on worker nodes"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_control_plane.id
}

resource "aws_security_group_rule" "nodes_ingress_alb_nodeport" {
  security_group_id        = aws_security_group.eks_nodes.id
  type                     = "ingress"
  description              = "Allow ALB to forward traffic to Kubernetes NodePort range"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "nodes_egress_all" {
  #checkov:skip=CKV_AWS_382:EKS control plane requires unrestricted outbound connectivity to AWS managed services.

  security_group_id = aws_security_group.eks_nodes.id
  type              = "egress"
  description       = "Allow all outbound traffic from worker nodes (ECR, S3, AWS APIs)"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ============================================================
# ALB SECURITY GROUP
# ============================================================
resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Security Group is attached by dependent Terraform resources in other modules.

  name        = "${local.name_prefix}-alb-sg"
  description = "Security Group for Application Load Balancer - allows HTTP/HTTPS from the internet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  #checkov:skip=CKV_AWS_260:HTTP port is intentionally exposed to redirect clients to HTTPS.

  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  description       = "Allow inbound HTTP traffic from the internet"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_ingress_https" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  description       = "Allow inbound HTTPS traffic from the internet"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress_all" {
  #checkov:skip=CKV_AWS_382:Application Load Balancer requires outbound connectivity to backend targets.

  security_group_id = aws_security_group.alb.id
  type              = "egress"
  description       = "Allow all outbound traffic from ALB to worker nodes"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ============================================================
# RDS SECURITY GROUP
# ============================================================
resource "aws_security_group" "rds" {
  #checkov:skip=CKV2_AWS_5:Security Group is attached by dependent Terraform resources in other modules.

  name        = "${local.name_prefix}-rds-sg"
  description = "Security Group for RDS PostgreSQL - allows inbound only from EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_ingress_nodes_postgres" {
  security_group_id        = aws_security_group.rds.id
  type                     = "ingress"
  description              = "Allow PostgreSQL access exclusively from EKS worker nodes"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "rds_egress_all" {
  #checkov:skip=CKV_AWS_382:Default outbound rule is acceptable for this development environment.

  security_group_id = aws_security_group.rds.id
  type              = "egress"
  description       = "Allow all outbound traffic from RDS"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
