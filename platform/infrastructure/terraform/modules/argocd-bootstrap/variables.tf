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

  validation {
    condition = contains(
      ["dev", "staging", "prod"],
      var.environment
    )

    error_message = "environment must be dev, staging, or prod."
  }
}

# ============================================================
# ArgoCD Project
# ============================================================
variable "argocd_project_name" {
  description = "Name of the ArgoCD Project used to group and manage applications"
  type        = string

  validation {
    condition     = length(trim(var.argocd_project_name, " ")) > 0
    error_message = "argocd_project_name cannot be empty."
  }
}

# ============================================================
# ArgoCD Helm Chart
# ============================================================
variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD will be installed"
  type        = string
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (pin for reproducibility)"
  type        = string
}

variable "argocd_server_insecure" {
  description = "Run ArgoCD server without TLS (true when ALB handles TLS termination)"
  type        = bool
}

variable "argocd_ha_enabled" {
  description = "Enable HA mode (multiple replicas). Set false for dev to save cost."
  type        = bool
}

# ============================================================
# argocd-apps Helm Chart (used to deploy the Root Application)
# ============================================================
variable "argocd_apps_chart_version" {
  description = "Version of the argocd-apps Helm chart used to create the Root App"
  type        = string
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
}

variable "gitops_root_app_path" {
  description = "Path in the repo containing child Application manifests (App of Apps)"
  type        = string
}

variable "gitops_repo_ssh_private_key" {
  description = <<-EOT
    SSH private key for accessing a private Git repository.
    Leave empty for public repos or HTTPS with no auth.
    Set via TF_VAR_gitops_repo_ssh_private_key — never commit this value.
  EOT
  type        = string
  sensitive   = true
}
