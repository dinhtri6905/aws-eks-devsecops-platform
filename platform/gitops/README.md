# platform/gitops

GitOps layer for the Cloud-Native Secure GitOps Platform on AWS EKS.

This directory contains all Kubernetes manifests, Helm values, and Kustomize configurations managed by ArgoCD. Once the Terraform infrastructure is provisioned, everything in this directory drives the full platform lifecycle — from cluster add-ons to application deployment.

---

## How It Works

```
terraform apply
      │
      └── EKS Cluster ready
            │
            └── ArgoCD bootstrapped (via Helm)
                  │
                  └── kubectl apply -f argocd/root-app.yaml   ← one-time manual step
                              │
                              │  ArgoCD reads argocd/applications/
                              │
                              ├── Wave 1 ── platform-services.yaml  → Metrics Server, AWS LBC
                              ├── Wave 2 ── security.yaml           → OPA Gatekeeper, Falco
                              ├── Wave 3 ── observability.yaml      → Prometheus, Grafana
                              └── Wave 4 ── online-boutique.yaml    → 13 microservices
```

ArgoCD syncs all child Applications automatically. Each Application either:
- Points directly at a **Helm chart** (platform tools), or
- Points at a **Kustomize overlay** (Online Boutique)

---

## Directory Structure

```
platform/gitops/
│
├── argocd/                          # ArgoCD App-of-Apps pattern
│   ├── root-app.yaml                # Entrypoint — apply this once after terraform apply
│   ├── projects/
│   │   └── platform.yaml           # AppProject: RBAC, allowed repos, allowed namespaces
│   └── applications/
│       ├── platform-services.yaml  # Wave 0: Metrics Server + AWS Load Balancer Controller
│       ├── security.yaml           # Wave 1: OPA Gatekeeper + Falco
│       ├── observability.yaml      # Wave 2: kube-prometheus-stack
│       └── online-boutique.yaml    # Wave 3: Online Boutique microservices
│
└── kustomize/
    ├── base/                        # Shared cluster-wide config
    ├── platform-services/           # Helm values for cluster add-ons
    ├── security/                    # Helm values + OPA policies
    ├── observability/               # Helm values + dashboards + alerts
    ├── applications/online-boutique # 13 microservice manifests (base)
    └── overlays/
        ├── dev/                     # Dev patches: replicas=1, dev config
        └── prod/                    # Prod patches: replicas=2, HPA, higher limits
```

---

## ArgoCD Layer

### `argocd/root-app.yaml`

The App of Apps entrypoint. Points to `argocd/applications/` in this repository. Apply once after `terraform apply`:

```bash
kubectl apply -f platform/gitops/argocd/root-app.yaml
```

ArgoCD then discovers and manages all child Applications automatically, including self-healing and drift detection.

### `argocd/projects/platform.yaml`

Defines the `platform` AppProject which:
- Whitelists all Helm chart repositories used by the platform
- Restricts deployments to specific namespaces (`kube-system`, `monitoring`, `gatekeeper-system`, `falco`, `online-boutique`, `argocd`)
- Allows cluster-scoped resources (Namespace, ClusterRole, CRD, IngressClass, Webhooks)

### `argocd/applications/`

Each file is an ArgoCD `Application` manifest with a sync wave annotation:

| File | Wave | Deploys | Namespace |
|---|---|---|---|
| `platform-services.yaml` | 1 | Metrics Server, AWS Load Balancer Controller | `kube-system` |
| `security.yaml` | 2 | OPA Gatekeeper, Falco | `gatekeeper-system`, `falco` |
| `observability.yaml` | 3 | kube-prometheus-stack | `monitoring` |
| `online-boutique.yaml` | 4 | Online Boutique (13 services) | `online-boutique` |

Sync waves guarantee ordering — Wave N does not start until Wave N-1 is healthy.

---

## Kustomize Layer

### `kustomize/base/`

Cluster-wide shared resources applied before any overlay:

| File | Purpose |
|---|---|
| `namespace.yaml` | Declares all namespaces (`monitoring`, `falco`, `gatekeeper-system`, `online-boutique`) |
| `common-labels.yaml` | Common label schema for all resources |
| `kustomization.yaml` | Root kustomization referencing the above |

### `kustomize/platform-services/`

Helm values files for cluster add-ons. These are referenced by `platform-services.yaml` (ArgoCD Application with `source.helm`), not rendered by Kustomize directly.

| Directory | Chart | Version | Purpose |
|---|---|---|---|
| `metrics-server/` | `metrics-server/metrics-server` | 3.12.1 | Provides CPU/Memory metrics for HPA and `kubectl top` |
| `aws-load-balancer-controller/` | `aws/aws-load-balancer-controller` | 1.8.1 | Watches Ingress resources and creates ALB on AWS |

> **Important:** `aws-load-balancer-controller/values.yaml` contains `<LBC_ROLE_ARN>` placeholder.
> Replace with the actual value before pushing:
> ```bash
> terraform output -raw lbc_role_arn
> ```

`ingressclass.yaml` defines the `alb` IngressClass consumed by all `frontend/ingress.yaml` resources.

### `kustomize/security/`

#### `opa-gatekeeper/`

OPA Gatekeeper enforces Policy-as-Code at admission time — any non-compliant resource is **rejected before it reaches the API server**.

**`values.yaml`** — Helm values for the Gatekeeper controller.

**`templates/`** — ConstraintTemplates define custom policy types (CRDs):

| Template | What it defines |
|---|---|
| `k8srequiredlabels.yaml` | Policy type: all resources must have specified labels |
| `k8srequiredresources.yaml` | Policy type: all containers must declare resource requests and limits |
| `k8snonroot.yaml` | Policy type: containers must not run as root |
| `k8sdisallowprivileged.yaml` | Policy type: privileged containers are disallowed |

**`constraints/`** — Constraint instances activate the policies against real namespaces:

| Constraint | Enforces |
|---|---|
| `require-labels.yaml` | All pods must have `app` and `environment` labels |
| `require-resource-limits.yaml` | All containers must declare `resources.limits` |
| `require-non-root.yaml` | `runAsNonRoot: true` required on all pods |
| `disallow-privileged.yaml` | `privileged: true` is blocked cluster-wide |

#### `falco/`

Falco runs as a DaemonSet on every node and detects runtime threats using eBPF:

| File | Purpose |
|---|---|
| `values.yaml` | Helm values: `driver.kind: modern_ebpf`, JSON output, Kubernetes metadata enrichment |
| `kustomization.yaml` | Kustomize entry for this directory |

### `kustomize/observability/kube-prometheus-stack/`

Deploys the full monitoring stack via the `kube-prometheus-stack` Helm chart (Prometheus + Grafana + Alertmanager + Node Exporter + kube-state-metrics in one release).

| Subdirectory | Contents |
|---|---|
| `values.yaml` | Helm values: retention 7d, gp3 persistent storage, Grafana admin password, service monitor selectors |
| `dashboards/` | Pre-built Grafana dashboard JSON files, auto-provisioned on startup |
| `alerts/` | PrometheusRule manifests for CPU, memory, and pod restart alerts |
| `servicemonitors/` | ServiceMonitor manifests telling Prometheus which endpoints to scrape |

**Dashboards included:**

| File | Dashboard |
|---|---|
| `cluster-overview.json` | Node count, pod count, CPU/memory cluster-wide |
| `node-metrics.json` | Per-node CPU, RAM, disk, network |
| `application-metrics.json` | Online Boutique request rate, latency, error rate |

**Alert rules included:**

| File | Fires when |
|---|---|
| `cpu-usage.yaml` | Node CPU > 80% for 5 minutes |
| `memory-usage.yaml` | Node memory > 85% for 5 minutes |
| `pod-restarts.yaml` | Pod restarts > 5 times in 1 hour |

**ServiceMonitors included:**

| File | Scrapes |
|---|---|
| `servicemonitors/kubernetes.yaml` | kube-apiserver, kubelet, coredns |
| `servicemonitors/online-boutique.yaml` | All Online Boutique pods via port annotation |

### `kustomize/applications/online-boutique/`

Base Kubernetes manifests for all 13 microservices. Each service directory contains:
- `deployment.yaml` — Deployment with health probes, security context, resource limits
- `service.yaml` — ClusterIP Service
- `kustomization.yaml` — Kustomize component entry

`frontend/` also includes `ingress.yaml` — creates the AWS ALB via Load Balancer Controller annotations.

**Service map and ports:**

| Service | Port | Protocol | Connects to |
|---|---|---|---|
| `frontend` | 8080 | HTTP | all downstream services |
| `cartservice` | 7070 | gRPC | `redis-cart:6379` |
| `redis-cart` | 6379 | TCP | — |
| `productcatalogservice` | 3550 | gRPC | — |
| `recommendationservice` | 8080 | gRPC | `productcatalogservice:3550` |
| `checkoutservice` | 5050 | gRPC | cart, product, shipping, payment, email, currency |
| `paymentservice` | 50051 | gRPC | — |
| `shippingservice` | 50051 | gRPC | — |
| `emailservice` | 5000→8080 | gRPC | — |
| `currencyservice` | 7000 | gRPC | — |
| `adservice` | 9555 | gRPC | — |
| `shoppingassistantservice` | 80 | HTTP | `productcatalogservice:3550` |
| `loadgenerator` | — | — | `frontend:80` |

> Note: `emailservice` container listens on `8080` but the Service exposes port `5000`. `checkoutservice` calls `emailservice:5000`.

**Security applied to every pod:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

### `kustomize/overlays/`

Overlays patch the base using Kustomize Strategic Merge Patch.

#### `overlays/dev/`

| File | What it does |
|---|---|
| `kustomization.yaml` | References base, applies `replicas-patch.yaml` to all Deployments, generates `online-boutique-env` ConfigMap with `ENVIRONMENT=dev` |
| `replicas-patch.yaml` | Sets `replicas: 1` on every Deployment — reduces cost in dev |
| `configmap-patch.yaml` | Placeholder for dev-specific config overrides |

#### `overlays/prod/`

| File | What it does |
|---|---|
| `kustomization.yaml` | References base, applies both patches, includes `hpa.yaml`, generates ConfigMap with `ENVIRONMENT=prod` |
| `replicas-patch.yaml` | Sets `replicas: 2` on every Deployment — minimum HA |
| `resource-limits-patch.yaml` | Increases CPU/memory limits for all containers |
| `hpa.yaml` | HPA for `frontend`, `cartservice`, `checkoutservice`, `productcatalogservice` — scales 2→10 pods at 60% CPU |

---

## Sync Wave Order

```
Wave  0  root-app.yaml          discovers all child Applications
   │
Wave  1  platform-services      Metrics Server + AWS LBC must be Running
   │                            ↳ Without LBC, all Ingress stay Pending forever
   │
Wave  2  security               OPA Gatekeeper webhooks active
   │                            ↳ All subsequent pods validated against policies
   │                            Falco eBPF probes loaded on all nodes
   │
Wave  3  observability          Prometheus scraping, Grafana dashboards live
   │                            ↳ Grafana needs Prometheus datasource to be ready
   │
Wave  4  online-boutique        All 13 services deployed
                                ↳ frontend Ingress → LBC → AWS ALB created
                                ↳ loadgenerator waits for frontend via initContainer
```

---

## Namespaces

| Namespace | Managed by | Contains |
|---|---|---|
| `kube-system` | ArgoCD Wave 0 | Metrics Server, AWS LBC |
| `gatekeeper-system` | ArgoCD Wave 1 | OPA Gatekeeper controller |
| `falco` | ArgoCD Wave 1 | Falco DaemonSet |
| `monitoring` | ArgoCD Wave 2 | Prometheus, Grafana, Alertmanager |
| `online-boutique` | ArgoCD Wave 3 | All 13 microservices |
| `argocd` | Terraform (bootstrap) | ArgoCD itself |

---

## Useful Commands

```bash
# Apply Root App (one-time after terraform apply)
kubectl apply -f platform/gitops/argocd/root-app.yaml

# Watch all ArgoCD Applications
kubectl get applications -n argocd

# Check sync status of a specific app
kubectl describe application online-boutique -n argocd

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Port-forward Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Get the ALB URL after online-boutique deploys
kubectl get ingress frontend -n online-boutique

# View OPA Gatekeeper constraint violations
kubectl get constraints

# View Falco runtime alerts
kubectl logs -l app.kubernetes.io/name=falco -n falco --tail=50

# Verify all pods in online-boutique namespace
kubectl get pods -n online-boutique

# Force a manual sync
argocd app sync online-boutique
```

---

## Before You Push

Replace the `<LBC_ROLE_ARN>` placeholder in `kustomize/platform-services/aws-load-balancer-controller/values.yaml` with the actual ARN from Terraform:

```bash
# Get the value
terraform -chdir=platform/infrastructure/terraform/environments/dev \
  output -raw lbc_role_arn

# Then edit the file
# serviceAccount.annotations.eks.amazonaws.com/role-arn: "<paste here>"
```

Without this, the AWS Load Balancer Controller pod will start but fail to create ALBs — all Ingress resources will remain in `Pending` state indefinitely.
