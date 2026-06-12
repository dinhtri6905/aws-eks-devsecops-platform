# =============================================================================
# MODULE: argocd-bootstrap / main.tf
# =============================================================================
#
# Resource creation order (enforced by depends_on):
#
#   ① kubernetes_namespace "argocd"
#       └── ② helm_release "argocd"          (argo-cd chart)
#               ├── ③ kubernetes_secret       (git repo credentials — optional)
#               └── ④ helm_release "root_app" (argocd-apps chart → Root Application)
#
# The Root Application (App of Apps) points at your GitOps repo.
# ArgoCD then takes over and continuously syncs everything else from Git.
#
# Providers required in the ROOT module (environments/dev/provider.tf):
#   - hashicorp/helm       >= 2.12
#   - hashicorp/kubernetes >= 2.27
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Labels applied to all Kubernetes resources managed by this module
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

  # Wait until all ArgoCD pods are running before proceeding
  timeout         = 600
  wait            = true
  atomic          = true  # rolls back on failure
  cleanup_on_fail = true

  values = [
    yamlencode({

      # Global 
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

      # ArgoCD Server 
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

      # Application Controller 
      # Reconciles all Applications — keep at 1 replica unless > 50 clusters
      controller = {
        replicas = 1
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { cpu = "1",    memory = "1Gi"   }
        }
      }

      # Repo Server 
      repoServer = {
        replicas = var.argocd_ha_enabled ? 2 : 1
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      # ApplicationSet Controller 
      applicationSet = {
        replicas = var.argocd_ha_enabled ? 2 : 1
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }

      # Redis 
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

      # Dex (SSO)
      # Disabled: SSO can be configured later (GitHub OAuth, Okta, etc.)
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
  # Only create when an SSH private key is provided
  count = var.gitops_repo_ssh_private_key != "" ? 1 : 0

  metadata {
    name      = "${local.name_prefix}-gitops-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = merge(local.common_labels, {
      # Required label for ArgoCD to discover repository credentials
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

# ============================================================
# ROOT APPLICATION — App of Apps pattern
# ============================================================
# Uses the official "argocd-apps" Helm chart to create an ArgoCD Application
# resource. This avoids the need for a kubectl/manifest provider.
#
# The Root App points at: gitops_repo_url / gitops_root_app_path
# That directory contains individual Application YAMLs for every platform
# component (Metrics Server, LBC, Prometheus, Grafana, OPA, Falco, etc.)
#
# ArgoCD then continuously syncs those Applications from Git — fully automated.
# ============================================================

resource "helm_release" "argocd_root_app" {
  name       = "${local.name_prefix}-root-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  timeout = 120

  # wait=false: the Application is created but ArgoCD syncs it asynchronously
  wait            = false
  atomic          = false
  cleanup_on_fail = false

  values = [
    yamlencode({
      applications = [
        {
          name      = "${local.name_prefix}-root"
          namespace = var.argocd_namespace
          project   = "default"

          # Finalizer ensures child apps are cleaned up when root app is deleted
          finalizers = ["resources-finalizer.argocd.argoproj.io"]

          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_repo_branch
            path           = var.gitops_root_app_path
          }

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = var.argocd_namespace
          }

          syncPolicy = {
            # Fully automated — ArgoCD will prune removed resources and self-heal drift
            automated = {
              prune    = true
              selfHeal = true
            }

            syncOptions = [
              "CreateNamespace=true",       # auto-create namespaces for child apps
              "PrunePropagationPolicy=foreground",
              "PruneLast=true",             # prune only after all resources are healthy
            ]

            # Exponential backoff retry — avoids hammering the API server on failures
            retry = {
              limit = 5
              backoff = {
                duration    = "5s"
                factor      = 2
                maxDuration = "3m"
              }
            }
          }
        }
      ]
    })
  ]

  # Root App can only be created after ArgoCD (and CRDs) are installed
  depends_on = [helm_release.argocd]
}
