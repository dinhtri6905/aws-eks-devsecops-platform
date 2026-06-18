# platform/gitops/kustomize/overlays

Environment-specific configuration for Online Boutique, expressed as Kustomize patches against the shared base in `applications/online-boutique/`. ArgoCD's `online-boutique` Application (sync-wave "4") points at one of these two directories — `overlays/dev/` today — rather than at the base directly.

Both overlays start from the same source and diverge only in replica counts, resource sizing, environment configuration, and (in prod) autoscaling — never in duplicated copies of the Deployment/Service manifests themselves.

---

## Directory Structure

```text
overlays/
├── dev/
│   ├── kustomization.yaml          # bases: applications/online-boutique + base/ + patches + configMapGenerator
│   ├── replicas-patch.yaml         # 1 replica per Deployment
│   ├── configmap-patch.yaml        # Placeholder for dev-specific config overrides
│   └── platform-values/
│       └── aws-lbc-values.yaml     # Dev VPC ID override for the AWS Load Balancer Controller
│
└── prod/
    ├── kustomization.yaml          # bases: applications/online-boutique + patches + hpa.yaml
    ├── replicas-patch.yaml         # 2 replicas per Deployment
    ├── resource-limits-patch.yaml  # Higher CPU/memory requests and limits
    └── hpa.yaml                    # HorizontalPodAutoscaler for 4 high-traffic services
```

---

## dev

Optimized for cost and fast iteration rather than resilience.

| Setting | Value |
|---|---|
| Replicas | 1 per Deployment (`replicas-patch.yaml`, applied to every `Deployment` via a `target` selector) |
| Environment config | `ENVIRONMENT=dev`, `LOG_LEVEL=info`, `ENABLE_PROFILER=0` (via `configMapGenerator` → `online-boutique-env` ConfigMap) |
| Label | `environment: dev` applied to every resource via `commonLabels` |
| Autoscaling | None |

`configmap-patch.yaml` is currently a placeholder (`data: {}`) — it exists as a patch target for dev-specific config overrides but does not yet override anything beyond what the `configMapGenerator` literals already set.

`platform-values/aws-lbc-values.yaml` holds a dev-specific `vpcId` override intended for the AWS Load Balancer Controller's Helm values. **Note:** this file is not currently wired into `overlays/dev/kustomization.yaml` — it exists as a value reference but is not consumed by any `patches`, `replacements`, or `helmCharts` entry yet, so the controller still relies on the `vpcId` set directly in `platform-services/aws-load-balancer-controller/values.yaml`.

---

## prod

Optimized for availability and headroom under real traffic.

| Setting | Value |
|---|---|
| Replicas | 2 per Deployment minimum (`replicas-patch.yaml`) |
| Resource sizing | 200m/128Mi request, 500m/256Mi limit per container (`resource-limits-patch.yaml`) — higher than the base manifests' per-service defaults |
| Environment config | `ENVIRONMENT=prod`, `LOG_LEVEL=warn`, `ENABLE_PROFILER=0` |
| Label | `environment: prod` applied to every resource via `commonLabels` |
| Autoscaling | 4 `HorizontalPodAutoscaler` resources (see below) |

### HorizontalPodAutoscaler

`hpa.yaml` defines CPU-based autoscaling for the four services expected to see the highest traffic:

| Service | Min replicas | Max replicas | Target CPU utilization |
|---|---|---|---|
| `frontend` | 2 | 10 | 60% |
| `cartservice` | 2 | 6 | 60% |
| `checkoutservice` | 2 | 6 | 60% |
| `productcatalogservice` | 2 | 6 | 60% |

These HPAs scale against the `Deployment` resources defined in `applications/online-boutique/`, and depend on Metrics Server (installed in `platform-services/`, sync-wave 1) being healthy before they can read CPU utilization.

---

## Patch Mechanism

Both overlays use the same `target`-selector patch pattern to apply a single patch file to every `Deployment` in the base, rather than writing one patch per service:

```yaml
patches:
  - path: replicas-patch.yaml
    target:
      kind: Deployment
```

The patch file's `metadata.name: not-used` and dummy `selector`/`template` fields are placeholders required by Kustomize's strategic-merge patch format — they are never applied verbatim; only the fields under `spec` (e.g. `replicas`, `containers[].resources`) are merged into each matching `Deployment`.

---

## Build & Verify

```bash
# Render the dev overlay (what ArgoCD applies today)
kustomize build platform/gitops/kustomize/overlays/dev/

# Render the prod overlay
kustomize build platform/gitops/kustomize/overlays/prod/

# Validate against the Kubernetes 1.33 schema
kustomize build platform/gitops/kustomize/overlays/dev/ | \
  kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.33.0
```
