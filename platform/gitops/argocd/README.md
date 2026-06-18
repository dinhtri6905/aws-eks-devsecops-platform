# platform/gitops/argocd

ArgoCD configuration for the Cloud-Native Secure GitOps Platform on AWS EKS.

This directory implements the **App of Apps** pattern — a single Root Application
watches this directory and automatically creates, updates, and deletes all child
Applications based on what exists in `applications/`. One `kubectl apply` is all
it takes to bring the entire platform to life.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [How It Works](#how-it-works)
- [Getting Started](#getting-started)
- [Root Application](#root-application)
- [AppProject](#appproject)
- [Child Applications](#child-applications)
  - [platform-services](#platform-services--wave-1)
  - [security](#security--wave-2)
  - [observability](#observability--wave-3)
  - [online-boutique](#online-boutique--wave-4)
- [Sync Wave Order](#sync-wave-order)
- [Sync Options Explained](#sync-options-explained)
- [ignoreDifferences Explained](#ignoredifferences-explained)
- [RBAC Roles](#rbac-roles)
- [Useful Commands](#useful-commands)

---

## Directory Structure

```
argocd/
├── root-app.yaml               # Entrypoint — apply this once after terraform apply
│
├── projects/
│   └── platform.yaml           # AppProject: RBAC, allowed repos, allowed namespaces
│
└── applications/               # Root App watches this directory
    ├── platform-services.yaml  # Wave 1: Metrics Server + AWS Load Balancer Controller
    ├── security.yaml           # Wave 2: OPA Gatekeeper + Falco
    ├── observability.yaml      # Wave 3: kube-prometheus-stack
    └── online-boutique.yaml    # Wave 4: Online Boutique microservices
```

---

## How It Works

```
terraform apply
      │
      └── ArgoCD bootstrapped on EKS cluster (via Helm)
            │
            └── kubectl apply -f argocd/root-app.yaml   ← one-time manual step
                        │
                        │  root-app watches argocd/applications/
                        │  and creates 4 child Applications
                        │
                        ├── Wave 1 ── platform-services  →  kube-system
                        │            Metrics Server, AWS Load Balancer Controller
                        │            (ALB ready before Ingress resources are applied)
                        │
                        ├── Wave 2 ── security           →  security / gatekeeper-system / falco
                        │            OPA Gatekeeper (admission control)
                        │            Falco (runtime threat detection)
                        │            (policies active before app workloads deploy)
                        │
                        ├── Wave 3 ── observability      →  monitoring
                        │            Prometheus, Grafana, Alertmanager
                        │            (metrics scraped from wave 4 onward)
                        │
                        └── Wave 4 ── online-boutique    →  online-boutique
                                     13 microservices via Kustomize dev overlay
                                     frontend Ingress → LBC creates AWS ALB
```

ArgoCD polls the Git repository every 3 minutes and automatically applies any
change committed to `main`. `selfHeal: true` reverts any manual change made
directly to the cluster back to what is in Git.

---

## Getting Started

### Prerequisites

- EKS cluster running (Terraform applied)
- ArgoCD installed on the cluster (bootstrapped by Terraform Helm provider)
- `kubectl` configured to point at the cluster
- AppProject applied before the Root App

### Step 1 — Apply the AppProject

```bash
kubectl apply -f platform/gitops/argocd/projects/platform.yaml
```

### Step 2 — Apply the Root Application

```bash
kubectl apply -f platform/gitops/argocd/root-app.yaml
```

That is the only manual step. ArgoCD takes over from here and deploys all four
child Applications in sync wave order.

### Step 3 — Monitor progress

```bash
# Watch all Applications
kubectl get applications -n argocd -w

# Or use the ArgoCD CLI
argocd app list

# Port-forward the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

---

## Root Application

**File:** `root-app.yaml`

```yaml
source:
  repoURL: https://github.com/dinhtri6905/aws-eks-devsecops-platform.git
  targetRevision: main
  path: platform/gitops/argocd/applications   # watches this directory

destination:
  namespace: argocd                            # child Applications are created here

syncPolicy:
  automated:
    prune: true       # removes Applications deleted from Git
    selfHeal: true    # reverts manual cluster changes back to Git state
```

The Root App itself carries `sync-wave: "0"` — it runs before all child
Applications. When ArgoCD processes `applications/`, it discovers the 4 child
Application manifests and creates them, each with their own sync wave.

**Retry policy:**
```
limit: 5 attempts
backoff: 5s → 10s → 20s → 40s → 80s  (factor: 2, max: 3m)
```

---

## AppProject

**File:** `projects/platform.yaml`

The `platform` AppProject defines the security boundary for all Applications in
this platform. ArgoCD will refuse to sync any Application that violates the
project's rules.

| Setting | Value | Purpose |
|---|---|---|
| `sourceRepos` | `github.com/dinhtri6905/aws-eks-devsecops-platform.git` | Only this repo is trusted as a source |
| `destinations` | `argocd`, `kube-system`, `monitoring`, `security`, `online-boutique` | Deployments restricted to these namespaces |
| `clusterResourceWhitelist` | `*/*` | Allows cluster-scoped resources (CRDs, ClusterRoles, IngressClass) |
| `orphanedResources.warn` | `true` | ArgoCD warns if cluster has resources not tracked in Git |

**RBAC Roles defined in AppProject:**

| Role | Group | Permissions |
|---|---|---|
| `admin` | `platform-admins` | Full sync, create, delete on all Applications |
| `readonly` | `platform-viewers` | `get` only — read-only access to Application state |

---

## Child Applications

### platform-services — Wave 1

**File:** `applications/platform-services.yaml`

| Property | Value |
|---|---|
| Sync wave | `1` |
| Source path | `platform/gitops/kustomize/platform-services` |
| Destination namespace | `kube-system` |
| Deploys | Metrics Server, AWS Load Balancer Controller |

**Why Wave 1 runs first:**

The AWS Load Balancer Controller must be running before any `Ingress` resource
is applied. Without it, the `frontend` Ingress will stay in `Pending` indefinitely.
Metrics Server must be ready before HPA in Wave 4 can function.

**Dependency on Terraform:**
The LBC requires an IRSA role ARN injected into its Helm values:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "<terraform output -raw lbc_role_arn>"
```
This must be filled before pushing to Git.

---

### security — Wave 2

**File:** `applications/security.yaml`

| Property | Value |
|---|---|
| Sync wave | `2` |
| Source path | `platform/gitops/kustomize/security` |
| Destination namespace | `security` |
| Deploys | OPA Gatekeeper, Falco |

**Why Wave 2 runs before observability and applications:**

OPA Gatekeeper installs a `ValidatingWebhookConfiguration` that intercepts all
`CREATE`/`UPDATE` requests to the API server. If Gatekeeper is deployed after
Online Boutique, pods would have been created without policy validation. By
deploying security in Wave 2, every pod in Wave 3 and Wave 4 is validated at
admission time.

**`ignoreDifferences` configured for:**

```yaml
ignoreDifferences:
  - kind: ValidatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle   # injected at runtime by cert-manager
      - /webhooks/1/clientConfig/caBundle
  - kind: MutatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle
```

Gatekeeper injects its CA bundle into webhook configs at runtime. Without
`ignoreDifferences`, ArgoCD would see these as out-of-sync and loop trying
to revert them.

---

### observability — Wave 3

**File:** `applications/observability.yaml`

| Property | Value |
|---|---|
| Sync wave | `3` |
| Source path | `platform/gitops/kustomize/observability/kube-prometheus-stack` |
| Destination namespace | `monitoring` |
| Deploys | Prometheus, Grafana, Alertmanager, Node Exporter, kube-state-metrics |

**Why Wave 3 runs after security:**

Gatekeeper policies (Wave 2) must be active so the Prometheus and Grafana pods
are validated against the same security constraints as all other workloads.

**`ServerSideApply: true`** is required because Prometheus Operator CRDs are
large and exceed the annotation size limit of client-side apply.

**`ignoreDifferences` configured for:**

```yaml
ignoreDifferences:
  - kind: StatefulSet
    jsonPointers:
      - /spec/volumeClaimTemplates   # Prometheus operator patches this at runtime
  - kind: ServiceMonitor
    jsonPointers:
      - /spec/endpoints              # operator normalises endpoint fields at runtime
```

Without these, ArgoCD would report the Application as `OutOfSync` on every
reconciliation loop due to fields mutated by the Prometheus Operator.

---

### online-boutique — Wave 4

**File:** `applications/online-boutique.yaml`

| Property | Value |
|---|---|
| Sync wave | `4` |
| Source path | `platform/gitops/kustomize/overlays/dev` |
| Destination namespace | `online-boutique` |
| Deploys | 13 microservices via Kustomize dev overlay |

**Why Wave 4 is last:**

All platform tools must be healthy before application workloads deploy:
- AWS LBC (Wave 1) must exist to handle the `frontend` Ingress → AWS ALB
- OPA Gatekeeper (Wave 2) must be enforcing policies before pods are admitted
- Prometheus (Wave 3) ServiceMonitors must exist to start scraping from day one

**`PrunePropagationPolicy: foreground`** ensures that when a service is removed
from the Kustomize overlay, its pods are fully terminated before ArgoCD marks
the sync as complete — prevents ghost endpoints in the ALB target group.

---

## Sync Wave Order

```
Wave 0   root-app           discovers and creates child Applications
  │
Wave 1   platform-services  Metrics Server + AWS LBC running and healthy
  │      └── prerequisite: LBC_ROLE_ARN in Helm values (from terraform output)
  │
Wave 2   security           Gatekeeper webhook active, Falco eBPF probes loaded
  │      └── all subsequent pods are admission-validated and runtime-monitored
  │
Wave 3   observability      Prometheus scraping, Grafana dashboards live
  │      └── ServiceMonitors pick up online-boutique pods from Wave 4 onward
  │
Wave 4   online-boutique    13 microservices deployed, ALB provisioned by LBC
         └── loadgenerator initContainer waits for frontend to be Ready
```

ArgoCD will not start a wave until all Applications in the previous wave reach
`Healthy` status. If any wave fails, later waves do not run.

---

## Sync Options Explained

All Applications share these `syncOptions`:

| Option | Effect |
|---|---|
| `CreateNamespace=true` | ArgoCD creates the destination namespace if it does not exist |
| `ApplyOutOfSyncOnly=true` | Only applies resources that are actually out of sync — reduces API server load and speeds up sync |
| `ServerSideApply=true` | Used on `security` and `observability` — required for large CRDs that exceed client-side apply annotation limits |
| `PrunePropagationPolicy=foreground` | Used on `platform-services` and `online-boutique` — waits for dependent resources to be deleted before marking prune complete |
| `RespectIgnoreDifferences=true` | Used on `security` — respects `ignoreDifferences` during sync, not just during health checks |

---

## ignoreDifferences Explained

Some Kubernetes controllers mutate resources at runtime in ways that are not
reflected in Git. Without `ignoreDifferences`, ArgoCD would permanently report
these Applications as `OutOfSync`.

| Application | Resource | Field | Why it changes at runtime |
|---|---|---|---|
| `security` | `ValidatingWebhookConfiguration` | `/webhooks/*/clientConfig/caBundle` | Gatekeeper cert-manager injects CA bundle |
| `security` | `MutatingWebhookConfiguration` | `/webhooks/0/clientConfig/caBundle` | Same as above |
| `observability` | `StatefulSet` | `/spec/volumeClaimTemplates` | Prometheus Operator patches VCT spec |
| `observability` | `ServiceMonitor` | `/spec/endpoints` | Prometheus Operator normalises endpoint fields |

---

## RBAC Roles

Access to ArgoCD Applications is controlled via the `platform` AppProject roles.

| Role | Group | Can do |
|---|---|---|
| `admin` | `platform-admins` | Sync, create, delete, update any Application in the `platform` project |
| `readonly` | `platform-viewers` | View Application status and resource tree — no sync or modify |

To assign a user to a group, add them to the `platform-admins` or
`platform-viewers` group in your SSO provider (GitHub Teams, Okta, etc.) and
configure ArgoCD's `argocd-cm` ConfigMap with the OIDC/Dex connector.

---

## Useful Commands

```bash
# Apply the AppProject (run before root-app)
kubectl apply -f platform/gitops/argocd/projects/platform.yaml

# Bootstrap the entire platform (run once)
kubectl apply -f platform/gitops/argocd/root-app.yaml

# Watch all Applications and their sync status
kubectl get applications -n argocd

# Get detailed status of a specific Application
argocd app get online-boutique

# Manually trigger a sync (skips the 3-minute poll interval)
argocd app sync root-app
argocd app sync platform-services
argocd app sync security
argocd app sync observability
argocd app sync online-boutique

# Sync all Applications at once
argocd app sync -l argocd.argoproj.io/app-namespace=argocd

# View sync history of an Application
argocd app history online-boutique

# Rollback to a previous sync
argocd app rollback online-boutique <HISTORY_ID>

# Check why an Application is OutOfSync
argocd app diff online-boutique

# Force refresh (re-fetch from Git immediately)
argocd app get online-boutique --refresh

# Delete an Application without pruning its resources
argocd app delete online-boutique --cascade=false

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
