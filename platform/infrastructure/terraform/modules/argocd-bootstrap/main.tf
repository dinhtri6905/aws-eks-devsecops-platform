# =============================================================================
# MODULE: argocd-bootstrap / main.tf
# =============================================================================
#
# Installs ArgoCD on the cluster via Helm and, optionally, a credentials
# secret for a private GitOps repository.
#
# Resource creation order (enforced by depends_on):
#
#   kubernetes_namespace "argocd"
#       └── helm_release "argocd"    (argo-cd chart)
#               └── kubernetes_secret (git repo credentials — optional)
#
# Terraform owns infrastructure only. The ArgoCD AppProject and the Root
# Application (App of Apps pattern) are deliberately not created here —
# they live as a static manifest at platform/gitops/argocd/root-app.yaml,
# applied once via `kubectl apply` when bootstrapping a new cluster. From
# that point on, ArgoCD reconciles both objects directly from Git, which
# keeps ArgoCD's own continuous status/operation writes out of the
# Terraform state loop entirely.
#
# Providers required in the root module:
#   - hashicorp/helm       >= 2.12
#   - hashicorp/kubernetes >= 2.27
#
# =============================================================================
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_labels = {
    "app.kubernetes.io/managed-by" = "Terraform"
    "app.kubernetes.io/part-of"    = local.name_prefix
  }
}

# ============================================================
# ARGOCD NAMESPACE
# ============================================================
resource "kubernetes_namespace" "argocd" {
  metadata {
    name   = var.argocd_namespace
    labels = local.common_labels
  }
}

# ============================================================
# ARGOCD HELM RELEASE
# ============================================================
# Chart: https://argoproj.github.io/argo-helm
# Ref:   https://artifacthub.io/packages/helm/argo/argo-cd
# ============================================================
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false

  timeout         = 600
  wait            = true
  atomic          = true
  cleanup_on_fail = true

  skip_crds = false

  values = [
    yamlencode({

      global = {
        logging = {
          level  = "info"
          format = "json"
        }
      }

      # ArgoCD config 
      configs = {

        params = {
          # ALB handles TLS — ArgoCD server runs plain HTTP internally
          "server.insecure" = tostring(var.argocd_server_insecure)
        }

        cm = {
          # Track resources by annotation (safer than label tracking)
          "application.resourceTrackingMethod" = "annotation"

          # Enable status badge on the ArgoCD UI
          "statusbadge.enabled" = "true"

          # Allow Kustomize to render helmCharts blocks (required for platform-services, observability, security)
          "kustomize.buildOptions" = "--enable-helm"

          # Exclude noisy Cilium resources from ArgoCD diff
          "resource.exclusions" = yamlencode([
            {
              apiGroups = ["cilium.io"]
              kinds     = ["CiliumIdentity"]
              clusters  = ["*"]
            }
          ])
        }

        rbac = {
          # Default role: read-only (least privilege)
          "policy.default" = "role:readonly"
        }
      }

      server = {
        replicas = var.argocd_ha_enabled ? 2 : 1

        # ClusterIP — traffic enters via AWS ALB (provisioned separately)
        service = {
          type = "ClusterIP"
        }

        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      # Reconciles all Applications — keep at 1 replica unless > 50 clusters
      controller = {
        replicas = 1
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { cpu = "1", memory = "1Gi" }
        }
      }

      repoServer = {
        replicas = var.argocd_ha_enabled ? 2 : 1
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      applicationSet = {
        replicas = var.argocd_ha_enabled ? 2 : 1
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }

      redis = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }

      # HA Redis (Sentinel) — only for prod
      "redis-ha" = {
        enabled = var.argocd_ha_enabled
      }

      # SSO can be configured later (GitHub OAuth, Okta, etc.)
      dex = {
        enabled = false
      }

    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# ============================================================
# GIT REPOSITORY SECRET (optional — only for private repos)
# ============================================================
# ArgoCD reads this secret to authenticate with the GitOps repository.
# Label "argocd.argoproj.io/secret-type: repository" is required by ArgoCD.
# ============================================================
resource "kubernetes_secret" "argocd_repo" {
  count = var.gitops_repo_ssh_private_key != "" ? 1 : 0

  metadata {
    name      = "${local.name_prefix}-gitops-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = merge(local.common_labels, {
      "argocd.argoproj.io/secret-type" = "repository"
    })
  }

  data = {
    type          = "git"
    url           = var.gitops_repo_url
    sshPrivateKey = var.gitops_repo_ssh_private_key
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}
