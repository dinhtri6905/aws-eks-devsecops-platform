variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in IRSA trust policy condition"
  type        = string
}

# ============================================================
# OIDC — provided by module.eks outputs
# ============================================================
variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider — required for IRSA trust policy"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (includes https://)"
  type        = string
}

# ============================================================
# LBC KUBERNETES IDENTITY
# Must match the ServiceAccount created by the LBC Helm chart
# ============================================================
variable "lbc_namespace" {
  description = "Kubernetes namespace where the LBC is deployed"
  type        = string
  default     = "kube-system"
}

variable "lbc_service_account_name" {
  description = "Kubernetes ServiceAccount name used by the LBC Helm chart"
  type        = string
  default     = "aws-load-balancer-controller"
}
