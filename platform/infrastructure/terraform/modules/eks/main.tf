locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_partition" "current" {}

# ============================================================
# CLOUDWATCH LOG GROUP
# Provision before the cluster so retention is controlled by Terraform
# ============================================================
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = {
    Name = "/aws/eks/${var.cluster_name}/cluster"
  }
}

# ============================================================
# EKS CLUSTER
# ============================================================
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access
  }

  # Grant the Terraform caller cluster-admin on creation
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # enable logging to easy debug
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Name = var.cluster_name
  }

  depends_on = [aws_cloudwatch_log_group.eks]
}

# ============================================================
# EKS MANAGED NODE GROUP
# ============================================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-node-group"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1 # Rolling update: A maximum of 1 node is unavailable at any given time.
  }

  labels = {
    environment = var.environment
    nodegroup   = "${local.name_prefix}-node-group"
  }

  tags = {
    Name                                            = "${local.name_prefix}-node-group"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

  # Ignore desired_size changes — cluster autoscaler manages this at runtime
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ============================================================
# OIDC PROVIDER
# Required for IRSA (IAM Roles for Service Accounts)
# Used by: EBS CSI Driver, AWS Load Balancer Controller, ArgoCD, etc.
# ============================================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.cluster_name}-oidc-provider"
  }
}

# ============================================================
# EBS CSI DRIVER — IRSA
# Allows the EBS CSI Driver to provision and manage EBS volumes
# ============================================================
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${local.name_prefix}-ebs-csi-driver-role"
  description        = "IRSA role for the EBS CSI Driver addon"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json

  tags = {
    Name = "${local.name_prefix}-ebs-csi-driver-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# ============================================================
# EKS ADDONS
# ============================================================

# VPC CNI — manages pod networking and IP allocation
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Bật NetworkPolicy enforcement
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
  
  tags = {
    Name = "${var.cluster_name}-vpc-cni"
  }
}

# CoreDNS — cluster DNS resolution for service discovery
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-coredns"
  }

  # CoreDNS requires at least one node to schedule on
  depends_on = [aws_eks_node_group.main]
}

# kube-proxy — manages network rules on each node
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-kube-proxy"
  }
}

# EBS CSI Driver — enables dynamic provisioning of EBS volumes (PersistentVolumes)
# Required by: Prometheus, Grafana, and any stateful workload using gp3 storage class
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-ebs-csi-driver"
  }

  depends_on = [aws_iam_role_policy_attachment.ebs_csi_driver]
}
