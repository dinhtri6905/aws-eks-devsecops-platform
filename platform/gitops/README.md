# platform/gitops

GitOps layer for the Cloud-Native Secure GitOps Platform on AWS EKS.

This directory contains all Kubernetes manifests, Helm values, and Kustomize
configurations managed by ArgoCD. Terraform provisions the infrastructure and
bootstraps ArgoCD automatically — once `terraform apply` completes, ArgoCD
takes ownership of everything in this directory and drives the full platform
lifecycle from cluster add-ons to application deployment.

---

## Table of Contents

- [How It Works](#how-it-works)
- [Directory Structure](#directory-structure)
- [ArgoCD Layer](#argocd-layer)
- [Kustomize Layer](#kustomize-layer)
- [Sync Wave Order](#sync-wave-order)
- [Namespaces](#namespaces)
- [Useful Commands](#useful-commands)
- [Before You Push](#before-you-push)

---

## How It Works

```
terraform apply
      │
      ├── EKS Cluster provisioned
      │
      └── argocd-bootstrap module
            ├── Installs ArgoCD via Helm
            ├── Applies AppProject (projects/platform.yaml)
            └── Applies Root Application (root-app.yaml)
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
│   ├── root-app.yaml                # Entrypoint — applied automatically by Terraform
│   ├── projects/
│   │   └── platform.yaml           # AppProject: RBAC, allowed repos, allowed namespaces
│   └── applications/
│       ├── platform-services.yaml  # Wave 1: Metrics Server + AWS Load Balancer Controller
│       ├── security.yaml           # Wave 2: OPA Gatekeeper + Falco
│       ├── observability.yaml      # Wave 3: kube-prometheus-stack
│       └── online-boutique.yaml    # Wave 4: Online Boutique microservices
│
└── kustomize/
    ├── base/                        # Shared cluster-wide config (namespaces, labels)
    ├── platform-services/           # Helm values for cluster add-ons
    ├── security/                    # Helm values + OPA policies + Falco custom rules
    ├── observability/               # Helm values + dashboards + alerts + servicemonitors
    ├── applications/online-boutique # 13 microservice base manifests
    └── overlays/
        ├── dev/                     # Dev: replicas=1, debug config, env=dev
        └── prod/                    # Prod: replicas=2, HPA, higher limits
```

---

## ArgoCD Layer

### `argocd/root-app.yaml`

The App of Apps entrypoint. Points to `argocd/applications/` in this repository.
Applied automatically by the Terraform `argocd-bootstrap` module — no manual
step required after `terraform apply`.

ArgoCD then discovers and manages all child Applications automatically, including
self-healing and drift detection.

### `argocd/projects/platform.yaml`

Defines the `platform` AppProject which:
- Whitelists all Helm chart repositories used by the platform
- Restricts deployments to specific namespaces (`kube-system`, `monitoring`,
  `gatekeeper-system`, `falco`, `online-boutique`, `argocd`)
- Allows cluster-scoped resources (Namespace, ClusterRole, CRD, IngressClass, Webhooks)

### `argocd/applications/`

Each file is an ArgoCD `Application` manifest with a sync wave annotation.
Sync waves guarantee ordering — Wave N does not start until Wave N-1 is healthy.

| File | Wave | Deploys | Namespace |
|---|---|---|---|
| `platform-services.yaml` | 1 | Metrics Server, AWS Load Balancer Controller | `kube-system` |
| `security.yaml` | 2 | OPA Gatekeeper, Falco | `gatekeeper-system`, `falco` |
| `observability.yaml` | 3 | kube-prometheus-stack | `monitoring` |
| `online-boutique.yaml` | 4 | Online Boutique (13 services) | `online-boutique` |

---

## Kustomize Layer

### `kustomize/base/`

Cluster-wide shared resources applied before any overlay:

| File | Purpose |
|---|---|
| `namespace.yaml` | Declares all namespaces (`monitoring`, `falco`, `gatekeeper-system`, `online-boutique`) |
| `common-labels.yaml` | Common label schema applied to all resources |
| `kustomization.yaml` | Root kustomization referencing the above |

### `kustomize/platform-services/`

Helm values files for cluster add-ons. Referenced by the `platform-services`
ArgoCD Application via `source.helm`, not rendered by Kustomize directly.

| Directory | Chart | Version | Purpose |
|---|---|---|---|
| `metrics-server/` | `metrics-server/metrics-server` | 3.12.1 | CPU/Memory metrics for HPA and `kubectl top` |
| `aws-load-balancer-controller/` | `aws/aws-load-balancer-controller` | 1.8.1 | Watches Ingress resources and creates ALB on AWS |

> **Important:** `aws-load-balancer-controller/values.yaml` contains a `<LBC_ROLE_ARN>`
> placeholder. Replace before pushing — see [Before You Push](#before-you-push).

`ingressclass.yaml` defines the `alb` IngressClass consumed by `frontend/ingress.yaml`.

### `kustomize/security/`

#### `opa-gatekeeper/`

OPA Gatekeeper enforces Policy-as-Code at admission time — any non-compliant
resource is **rejected before it reaches the API server**.

**`values.yaml`** — Helm values for the Gatekeeper controller.

**`templates/`** — ConstraintTemplates register custom policy types as CRDs (Wave 1):

| Template | Kind | What it enforces |
|---|---|---|
| `k8srequiredlabels.yaml` | `K8sRequiredLabels` | Required labels must be present with values matching a regex |
| `k8srequiredresources.yaml` | `K8sRequiredResources` | All containers must declare CPU and memory requests and limits |
| `k8snonroot.yaml` | `K8sRequireNonRoot` | `runAsNonRoot: true` must be set at pod or container level |
| `k8sdisallowprivileged.yaml` | `K8sBlockPrivileged` | `securityContext.privileged: true` is blocked |
| `k8sdisallowedtags.yaml` | `K8sDisallowedTags` | Image tags in the disallowed list (`:latest`) are rejected |
| `k8sreadonlyrootfs.yaml` | `K8sReadOnlyRootFS` | `readOnlyRootFilesystem: true` must be set |
| `k8sallowedrepos.yaml` | `K8sAllowedRepos` | Images must come from an allowed registry prefix |

**`constraints/`** — Constraint instances activate the policies (Wave 2):

| Constraint | Enforces |
|---|---|
| `require-labels.yaml` | All pods in `online-boutique` must have the `app` label |
| `require-resource-limits.yaml` | All containers must declare `resources.limits` |
| `require-non-root.yaml` | `runAsNonRoot: true` required on all pods |
| `disallow-privileged.yaml` | `privileged: true` is blocked cluster-wide |
| `disallow-latest-tag.yaml` | `:latest` image tag is blocked on all pods |
| `require-read-only-root-filesystem.yaml` | `readOnlyRootFilesystem: true` required |
| `allow-ecr-and-trusted-registries-only.yaml` | Only ECR and approved public registries allowed |

#### `falco/`

Falco runs as a DaemonSet on every node and detects runtime threats using eBPF.
Custom detection rules are decoupled from the Helm chart — they live in a
ConfigMap that Falco hot-reloads via inotify without requiring a pod restart.

| File | Purpose |
|---|---|
| `kustomization.yaml` | helmCharts block + ConfigMap reference |
| `values.yaml` | Helm values: `driver.kind: ebpf`, extraVolumes to mount custom rules |
| `custom-rules/custom-rules.yaml` | ConfigMap with 10 custom detection rules (MITRE-tagged) |

**Custom rules covered:**

| Rule | Priority | MITRE |
|---|---|---|
| Shell Spawned in Container | CRITICAL | T1059 |
| Package Manager Execution | WARNING | T1546 |
| Sensitive File Read | CRITICAL | T1552 |
| Unexpected Outbound Connection | NOTICE | T1048 |
| Write Below Binary Directory | CRITICAL | T1574 |
| Unexpected Container in Namespace | WARNING | T1190 |
| Setuid/Setgid Bit Set | CRITICAL | T1548 |
| Cryptomining Process | CRITICAL | T1496 |
| Service Account Token Write | CRITICAL | T1528 |
| Drift — New Binary Executed | WARNING | T1543 |

### `kustomize/observability/kube-prometheus-stack/`

Deploys the full monitoring stack via a single Helm chart release
(Prometheus + Grafana + Alertmanager + Node Exporter + kube-state-metrics).

| Path | Contents |
|---|---|
| `values.yaml` | Helm values: 7d retention, gp3 storage, Grafana admin config, selector flags |
| `dashboards/` | Grafana dashboard ConfigMaps — auto-provisioned via sidecar |
| `alerts/` | PrometheusRule manifests for CPU, memory, and pod restart alerts |
| `servicemonitors/` | ServiceMonitor manifests for cluster components and Online Boutique |

**Grafana dashboards:**

| File | Shows |
|---|---|
| `cluster-overview.yaml` | Node count, pod count, cluster-wide CPU/memory, restarts per namespace |
| `node-metrics.yaml` | Per-node CPU%, Memory%, Disk%, Network Rx/Tx |
| `application-metrics.yaml` | Online Boutique: running pods, restarts, per-service CPU and Memory |

**Alert rules:**

| File | Alerts | Fires when |
|---|---|---|
| `cpu-usage.yaml` | `NodeCPUHighWarning`, `NodeCPUHighCritical`, `ContainerCPUThrottling` | CPU > 80%/90% for 5m, throttled > 25% for 10m |
| `memory-usage.yaml` | `NodeMemoryHighWarning`, `NodeMemoryHighCritical`, `ContainerMemoryNearLimit` | Memory > 85%/95% for 5m, container > 90% limit |
| `pod-restarts.yaml` | `PodCrashLooping`, `PodCrashLoopingCritical`, `PodNotReady` | > 5/15 restarts in 1h, not ready > 5m |

**ServiceMonitors:**

| File | Scrapes |
|---|---|
| `kubernetes.yaml` | kubelet (metrics + cadvisor), CoreDNS |
| `online-boutique.yaml` | All services in `online-boutique` namespace |

### `kustomize/applications/online-boutique/`

Base Kubernetes manifests for all 13 workloads. Each service directory contains
a `deployment.yaml`, `service.yaml`, and `kustomization.yaml`. The `frontend/`
directory also includes `ingress.yaml` which creates the AWS ALB via Load
Balancer Controller annotations.

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

> `emailservice` container listens on `8080` but the Service exposes port `5000`.
> `checkoutservice` calls `emailservice:5000`.

> `redis-cart` uses `runAsUser: 999` (Redis UID) instead of 1000 to avoid
> permission errors when writing to `/data`.

**Security context applied to every pod:**

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
| `kustomization.yaml` | References base, applies patches, generates `online-boutique-env` ConfigMap with `ENVIRONMENT=dev` |
| `replicas-patch.yaml` | Sets `replicas: 1` on every Deployment — reduces cost in dev |
| `configmap-patch.yaml` | Placeholder for dev-specific config overrides |

#### `overlays/prod/`

| File | What it does |
|---|---|
| `kustomization.yaml` | References base, applies all patches, includes `hpa.yaml`, generates ConfigMap with `ENVIRONMENT=prod` |
| `replicas-patch.yaml` | Sets `replicas: 2` on every Deployment — minimum HA |
| `resource-limits-patch.yaml` | Increases CPU/memory limits for all containers |
| `hpa.yaml` | HPA for `frontend`, `cartservice`, `checkoutservice`, `productcatalogservice` — scales 2→10 pods at 60% CPU |

---

## Sync Wave Order

```
Wave  0  root-app              discovers all child Applications (Terraform-applied)
   │
Wave  1  platform-services     Metrics Server + AWS LBC running and healthy
   │                           ↳ Without LBC, all Ingress stay Pending forever
   │
Wave  2  security              OPA Gatekeeper webhooks active
   │                           ↳ All subsequent pods validated against 7 policies
   │                           Falco eBPF probes loaded, 10 custom rules active
   │
Wave  3  observability         Prometheus scraping, Grafana dashboards live
   │                           ↳ ServiceMonitors pick up Wave 4 pods automatically
   │
Wave  4  online-boutique       13 services deployed via Kustomize dev overlay
                               ↳ frontend Ingress → LBC → AWS ALB provisioned
                               ↳ loadgenerator waits for frontend via initContainer
```

ArgoCD will not start a wave until all Applications in the previous wave are `Healthy`.

---

## Namespaces

| Namespace | Managed by | Contains |
|---|---|---|
| `argocd` | Terraform bootstrap | ArgoCD itself |
| `kube-system` | ArgoCD Wave 1 | Metrics Server, AWS LBC |
| `gatekeeper-system` | ArgoCD Wave 2 | OPA Gatekeeper controller + webhook |
| `falco` | ArgoCD Wave 2 | Falco DaemonSet + custom rules ConfigMap |
| `monitoring` | ArgoCD Wave 3 | Prometheus, Grafana, Alertmanager, Node Exporter |
| `online-boutique` | ArgoCD Wave 4 | All 13 microservices |

---

## Useful Commands

```bash
# Verify ArgoCD is running after terraform apply
kubectl get pods -n argocd

# Watch all Applications sync in real time
kubectl get applications -n argocd -w

# Check sync status of a specific Application
kubectl describe application online-boutique -n argocd

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080

# Port-forward Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Open http://localhost:3000 (admin / admin)

# Get the ALB URL after online-boutique deploys
kubectl get ingress frontend -n online-boutique

# View OPA Gatekeeper constraint violations
kubectl get constraints

# View Falco runtime alerts (live)
kubectl logs -l app.kubernetes.io/name=falco -n falco -f

# Verify all pods in online-boutique namespace
kubectl get pods -n online-boutique

# Force a manual sync
argocd app sync online-boutique

# Rollback to a previous sync
argocd app history online-boutique
argocd app rollback online-boutique <HISTORY_ID>
```

---

## Before You Push

Replace the `<LBC_ROLE_ARN>` placeholder in
`kustomize/platform-services/aws-load-balancer-controller/values.yaml`
with the actual ARN from Terraform:

```bash
# Get the value
terraform -chdir=platform/infrastructure/terraform/environments/dev \
  output -raw lbc_role_arn

# Edit the values file — replace the placeholder
# serviceAccount.annotations."eks.amazonaws.com/role-arn": "<paste ARN here>"
```

Without this, the AWS Load Balancer Controller pod will start but fail to create
ALBs — all Ingress resources will remain in `Pending` state indefinitely.
