# platform/gitops/kustomize

Kustomize manifests for everything ArgoCD deploys onto the EKS cluster. This is the GitOps half of the platform: Terraform provisions AWS and bootstraps ArgoCD, and from that point on, everything under this directory is what ArgoCD reconciles the cluster against.

Each top-level subdirectory (or nested subdirectory, for `security/` and `observability/`) corresponds to one of the ten ArgoCD child Applications declared in `platform/gitops/argocd/applications/`, deployed in strict sync-wave order across eight waves (0–7).

---

## Directory Structure

```text
kustomize/
├── base/                              # Shared namespaces + common labels (consumed by overlays)
├── platform-services/                 # Metrics Server, AWS LBC, Argo Rollouts — wave 1
├── security/
│   ├── opa-gatekeeper/
│   │   ├── install/                   # Gatekeeper controller + CRDs — wave 2
│   │   │   └── templates/             # ConstraintTemplates — wave 4
│   │   └── policies/                  # Constraints (7 policies) — wave 5
│   ├── falco/                         # Falco DaemonSet — wave 4
│   └── network-policies/              # NetworkPolicies — wave 5
├── observability/
│   ├── crds/                          # Prometheus Operator CRDs — wave 3
│   └── kube-prometheus-stack/         # Prometheus, Grafana, Alertmanager — wave 6
├── applications/online-boutique/      # Base manifests for all 11 Online Boutique microservices
└── overlays/
    ├── dev/                           # Active environment — references base + applications/online-boutique — wave 7
    └── prod/                          # Production environment — HPA, higher replicas, stricter limits
```

Each subdirectory has its own README with implementation-level detail; this file covers how they fit together.

---

## Sync Wave Order

```text
wave 0 ── argocd-config                        ArgoCD's own RBAC/projects/notifications config
wave 1 ── platform-services                    Metrics Server, AWS Load Balancer Controller, Argo Rollouts
wave 2 ── gatekeeper-install                   OPA Gatekeeper controller + CRDs
wave 3 ── observability-crds                   Prometheus Operator CRDs
wave 4 ── gatekeeper-templates, falco          7 ConstraintTemplates · Falco DaemonSet (parallel)
wave 5 ── gatekeeper-policies, network-policies 7 Constraints · NetworkPolicies (parallel)
wave 6 ── observability                        kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
wave 7 ── online-boutique                      11 Online Boutique microservices, via overlays/dev/
```

This order exists because later waves depend on earlier ones: the Gatekeeper controller (wave 2) must exist before its ConstraintTemplates (wave 4) can register, and those templates must exist before Constraints (wave 5) can instantiate them — so admission enforcement is fully active before any application Pod is created in wave 7 (otherwise those Pods would bypass policy enforcement entirely). Likewise, the Prometheus Operator CRDs (wave 3) must exist before the Helm release in wave 6 can create any ServiceMonitor, and Metrics Server (wave 1) must be healthy before the prod overlay's HorizontalPodAutoscaler resources can read CPU utilization. `gatekeeper-templates`/`falco` (wave 4) and `gatekeeper-policies`/`network-policies` (wave 5) sync in parallel within their wave, since neither pair depends on the other — only on the wave before it.

---

## How a Layer Reaches the Cluster

```text
ArgoCD child Application (e.g. online-boutique.yaml)
        │  spec.source.path: platform/gitops/kustomize/overlays/dev
        ▼
kustomize build <path>
        │  resolves bases, patches, helmCharts, configMapGenerator
        ▼
kubectl apply --server-side
        │
        ▼
Live cluster state
```

`platform-services/`, the `opa-gatekeeper/install/`, `opa-gatekeeper/install/templates/`, `opa-gatekeeper/policies/`, `falco/`, and `network-policies/` subpaths of `security/`, and the `crds/` and `kube-prometheus-stack/` subpaths of `observability/` are each referenced directly by their own ArgoCD Application. `online-boutique` is the one exception: its Application points at an **overlay** (`overlays/dev/`), which in turn pulls in `applications/online-boutique/` as a Kustomize base — this is what lets the same service manifests be reused, unmodified, across dev and prod.

---

## Where Each Subdirectory's Detail Lives

| Subdirectory | What it covers |
|---|---|
| [`base/`](./base/README.md) | Shared namespaces and the common label set every layer inherits |
| [`platform-services/`](./platform-services/README.md) | Metrics Server, AWS Load Balancer Controller, and Argo Rollouts Helm installs, IRSA wiring, the cluster's `IngressClass` |
| [`security/`](./security/README.md) | OPA Gatekeeper install vs. templates vs. policies split, Falco rules, NetworkPolicies, and how they complement each other |
| [`observability/`](./observability/README.md) | Prometheus Operator CRDs, kube-prometheus-stack Helm values, custom dashboards, alert rules, and ServiceMonitors |
| [`applications/online-boutique/`](./applications/online-boutique/README.md) | Per-service Deployment/Service/Ingress manifests, images, ports, and security context baseline |
| [`overlays/`](./overlays/README.md) | What dev and prod each patch on top of the application base, and the HPA configuration in prod |

---

## Useful Commands

```bash
# Render any layer locally before pushing
kustomize build platform/gitops/kustomize/overlays/dev/
kustomize build platform/gitops/kustomize/security/opa-gatekeeper/install/
kustomize build platform/gitops/kustomize/security/opa-gatekeeper/policies/
kustomize build platform/gitops/kustomize/security/falco/
kustomize build platform/gitops/kustomize/security/network-policies/
kustomize build platform/gitops/kustomize/observability/crds/
kustomize build platform/gitops/kustomize/observability/kube-prometheus-stack/

# Check what ArgoCD currently has synced (all 10 child Applications)
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'

# Cross-check each Application's actual sync-wave annotation against the table above
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}'
```
