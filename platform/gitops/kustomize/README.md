# platform/gitops/kustomize

Kustomize manifests for everything ArgoCD deploys onto the EKS cluster. This is the GitOps half of the platform: Terraform provisions AWS and bootstraps ArgoCD, and from that point on, everything under this directory is what ArgoCD reconciles the cluster against.

Each top-level subdirectory corresponds to one of the four ArgoCD child Applications declared in `platform/gitops/argocd/applications/`, deployed in strict sync-wave order.

---

## Directory Structure

```text
kustomize/
├── base/                        # Shared namespaces + common labels (consumed by overlays)
├── platform-services/           # Metrics Server, AWS Load Balancer Controller — wave 1
├── security/                    # OPA Gatekeeper, Falco — wave 2
├── observability/                # kube-prometheus-stack: Prometheus, Grafana, Alertmanager — wave 3
├── applications/online-boutique/ # Base manifests for all 13 Online Boutique workloads
└── overlays/
    ├── dev/                      # Active environment — references base + applications/online-boutique
    └── prod/                     # Production environment — HPA, higher replicas, stricter limits
```

Each subdirectory has its own README with implementation-level detail; this file covers how they fit together.

---

## Sync Wave Order

```text
wave 1 ── platform-services    Metrics Server, AWS Load Balancer Controller
wave 2 ── security             OPA Gatekeeper (7 ConstraintTemplates + 7 Constraints), Falco
wave 3 ── observability        kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
wave 4 ── online-boutique      13 Online Boutique workloads, via overlays/dev/
```

This order exists because later waves depend on earlier ones: Gatekeeper's admission webhook must be running before application Pods are created (or those Pods bypass policy enforcement entirely), Prometheus's ServiceMonitors must exist before there's anything useful to scrape, and Metrics Server must be healthy before the prod overlay's HorizontalPodAutoscaler resources can read CPU utilization.

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

`platform-services/`, `security/`, and `observability/` are each referenced directly by their ArgoCD Application. `online-boutique` is the one exception: its Application points at an **overlay** (`overlays/dev/`), which in turn pulls in `applications/online-boutique/` as a Kustomize base — this is what lets the same service manifests be reused, unmodified, across dev and prod.

---

## Where Each Subdirectory's Detail Lives

| Subdirectory | What it covers |
|---|---|
| [`base/`](./base/README.md) | Shared namespaces and the common label set every layer inherits |
| [`platform-services/`](./platform-services/README.md) | Metrics Server and AWS Load Balancer Controller Helm installs, IRSA wiring, the cluster's `IngressClass` |
| [`security/`](./security/README.md) | OPA Gatekeeper ConstraintTemplates/Constraints, Falco rules, and how the two complement each other |
| [`observability/`](./observability/README.md) | kube-prometheus-stack Helm values, custom dashboards, alert rules, and ServiceMonitors |
| [`applications/online-boutique/`](./applications/online-boutique/README.md) | Per-service Deployment/Service/Ingress manifests, images, ports, and security context baseline |
| [`overlays/`](./overlays/README.md) | What dev and prod each patch on top of the application base, and the HPA configuration in prod |

---

## Useful Commands

```bash
# Render any layer locally before pushing
kustomize build platform/gitops/kustomize/overlays/dev/
kustomize build platform/gitops/kustomize/security/
kustomize build platform/gitops/kustomize/observability/kube-prometheus-stack/

# Check what ArgoCD currently has synced
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'
```
