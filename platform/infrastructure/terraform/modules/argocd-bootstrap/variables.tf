# =============================================================================
# MODULE: argocd-bootstrap
# DESCRIPTION: Installs ArgoCD via Helm, creates a private Git repo secret,
#              and bootstraps the Root Application (App of Apps pattern).
#              Uses only official HashiCorp providers — no kubectl provider.
# =============================================================================

# ============================================================
# General
# ============================================================
variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

# ============================================================
# ArgoCD Helm Chart
# ============================================================
variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD will be installed"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (pin for reproducibility)"
  type        = string
  default     = "7.6.8"
}

variable "argocd_server_insecure" {
  description = "Run ArgoCD server without TLS (true when ALB handles TLS termination)"
  type        = bool
  default     = true
}

variable "argocd_ha_enabled" {
  description = "Enable HA mode (multiple replicas). Set false for dev to save cost."
  type        = bool
  default     = false
}

# ============================================================
# argocd-apps Helm Chart (used to deploy the Root Application)
# ============================================================
variable "argocd_apps_chart_version" {
  description = "Version of the argocd-apps Helm chart used to create the Root App"
  type        = string
  default     = "2.0.2"
}

# ============================================================
# GitOps Repository
# ============================================================
variable "gitops_repo_url" {
  description = "URL of the GitOps repository that ArgoCD will watch (HTTPS or SSH)"
  type        = string

  validation {
    condition = (
      can(regex("^https://", var.gitops_repo_url)) ||
      can(regex("^git@", var.gitops_repo_url))
    )
    error_message = "gitops_repo_url must start with 'https://' or 'git@'."
  }
}

variable "gitops_repo_branch" {
  description = "Git branch ArgoCD will track for the Root Application"
  type        = string
  default     = "main"
}

variable "gitops_root_app_path" {
  description = "Path in the repo containing child Application manifests (App of Apps)"
  type        = string
  default     = "platform/gitops/argocd/apps"
}

variable "gitops_repo_ssh_private_key" {
  description = <<-EOT
    SSH private key for accessing a private Git repository.
    Leave empty for public repos or HTTPS with no auth.
    Set via TF_VAR_gitops_repo_ssh_private_key — never commit this value.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}
