# platform/gitops/kustomize/base

Shared foundation layer for the GitOps tree. Every other layer — `platform-services/`, `security/`, `observability/`, and `applications/online-boutique/` — is composed on top of this base by `overlays/dev/` and `overlays/prod/`.

---

## Directory Structure

```text
base/
├── kustomization.yaml     # Declares the namespace resource + commonLabels
├── namespace.yaml          # The five namespaces used across the platform
└── common-labels.yaml      # Reference copy of the label set applied by kustomization.yaml
```

---

## What This Layer Provides

### Namespaces

`namespace.yaml` declares the five namespaces the platform deploys into:

| Namespace | Platform layer | Notes |
|---|---|---|
| `online-boutique` | Applications | Hosts all 13 Online Boutique workloads |
| `monitoring` | Observability | Prometheus, Grafana, Alertmanager |
| `security` | Security | Reserved for security-layer resources |
| `gatekeeper-system` | Security | Labeled `admission.gatekeeper.sh/ignore: "true"` so Gatekeeper does not enforce policy on itself |
| `falco` | Security | Falco DaemonSet |

Declaring these explicitly (rather than relying solely on ArgoCD's `CreateNamespace=true` sync option) keeps labels consistent across environments and lets the common label set in `kustomization.yaml` apply to the namespace objects themselves.

### Common Labels

`kustomization.yaml` applies the following labels to every resource built from this base, and to anything that includes it as a base:

```yaml
app.kubernetes.io/part-of: aws-eks-devsecops-platform
app.kubernetes.io/managed-by: argocd
project: eks-devsecops
```

`common-labels.yaml` is not consumed by Kustomize directly — it exists as a standalone reference copy of that label set so other layers (which define their own `commonLabels` rather than inheriting from `base/`) can mirror the same convention.

---

## How It's Used

`base/` is not deployed on its own and has no corresponding ArgoCD Application. It is consumed as a Kustomize base by the environment overlays:

```text
overlays/dev/  ──┐
                 ├──► base/  (namespaces + common labels)
overlays/prod/ ──┘
```

Any resource that needs to exist before its owning layer syncs — most importantly the namespaces — should be added here rather than duplicated per-layer.

```text
overlays/dev/kustomization.yaml
  → bases: overlays/dev/applications/online-boutique/kustomization.yaml   (commonLabels: environment: dev)
      → bases: gitops/kustomize/applications/online-boutique/kustomization.yaml   (commonLabels: project, managed-by)
          → cartservice/, checkoutservice/, frontend/ (rollout.yaml có sẵn app.kubernetes.io/part-of viết cứng)
```