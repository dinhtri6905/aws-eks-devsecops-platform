# =============================================================================
# MODULE: argocd-bootstrap / main.tf
# =============================================================================
#
# Resource creation order (enforced by depends_on):
#
#   ① kubernetes_namespace "argocd"
#       └── ② helm_release "argocd"              (argo-cd chart)
#               ├── ③ kubernetes_secret           (git repo credentials — optional)
#               └── ④ kubernetes_manifest "root_app" (Application CRD → Root Application)
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
  atomic          = true # rolls back on failure
  cleanup_on_fail = true

  skip_crds = false

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
          "server.insecure"       = tostring(var.argocd_server_insecure)
          "kustomize.enable-helm" = "true"
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
          limits   = { cpu = "1", memory = "1Gi" }
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
# Creates the ArgoCD Application CRD directly via the Kubernetes provider,
# bypassing the "argocd-apps" Helm chart.
#
# NOTE: The "argocd-apps" chart (tested on 2.0.2 and 2.0.5) has a confirmed
# bug where the rendered manifest fails Kubernetes API submission with:
#   "unable to decode: json: cannot unmarshal number into Go struct field
#    ObjectMeta.metadata.name of type string"
# This occurs even when all values (including retry.limit/retry.backoff.factor)
# are explicitly passed as quoted strings — confirmed via TF_LOG=DEBUG showing
# a fully valid, all-string values.yaml still failing at chart render time.
# Using kubernetes_manifest avoids the chart's Go template layer entirely.
#
# The Root App points at: gitops_repo_url / gitops_root_app_path
# That directory contains individual Application YAMLs for every platform
# component (Metrics Server, LBC, Prometheus, Grafana, OPA, Falco, etc.)
#
# ArgoCD then continuously syncs those Applications from Git — fully automated.
# ============================================================
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = "${local.name_prefix}-root"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }

    spec = {
      project = var.argocd_project_name

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
        automated = {
          prune    = true
          selfHeal = true
        }

        syncOptions = [
          "CreateNamespace=true",
          "PrunePropagationPolicy=foreground",
          "PruneLast=true",
          "ServerSideApply=true",
        ]

        retry = {
          limit = "5"
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  }

  # Root App can only be created after ArgoCD (and its CRDs) are installed
  depends_on = [helm_release.argocd]
}
