# =============================================================================
# MODULE: argocd-bootstrap
# DESCRIPTION: Installs ArgoCD via Helm and creates an optional private Git
#              repo credentials secret. The AppProject and Root Application
#              live as a static manifest at platform/gitops/argocd/root-app.yaml,
#              applied once via kubectl — not managed by this module.
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
# Reference value only — must match spec.project in
# platform/gitops/argocd/root-app.yaml.
variable "argocd_project_name" {
  description = "ArgoCD AppProject name used to group platform Applications. Must match platform/gitops/argocd/root-app.yaml."
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
  description = "Git branch ArgoCD tracks for the Root Application"
  type        = string
}

# Reference value only — must match spec.source.path in
# platform/gitops/argocd/root-app.yaml.
variable "gitops_root_app_path" {
  description = "Path in the repo containing child Application manifests. Must match platform/gitops/argocd/root-app.yaml."
  type        = string
  default     = "platform/gitops/argocd/applications"
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
