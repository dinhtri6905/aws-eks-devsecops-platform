# platform/gitops/argocd

ArgoCD configuration for the Cloud-Native Secure GitOps Platform on AWS EKS.

This directory implements the **App of Apps** pattern — a single Root Application
watches this directory and automatically creates, updates, and deletes all child
Applications based on what exists in `applications/`. Terraform bootstraps ArgoCD
and applies the Root Application automatically — no manual steps required after
`terraform apply`.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [How It Works](#how-it-works)
- [Getting Started](#getting-started)
- [Root Application](#root-application)
- [AppProject](#appproject)
- [Child Applications](#child-applications)
  - [argocd-config](#argocd-config--wave-0)
  - [platform-services](#platform-services--wave-1)
  - [gatekeeper-install](#gatekeeper-install--wave-2)
  - [observability-crds](#observability-crds--wave-3)
  - [gatekeeper-templates](#gatekeeper-templates--wave-4)
  - [falco](#falco--wave-4)
  - [gatekeeper-policies](#gatekeeper-policies--wave-5)
  - [network-policies](#network-policies--wave-5)
  - [observability](#observability--wave-6)
  - [online-boutique](#online-boutique--wave-7)
- [Sync Wave Order](#sync-wave-order)
- [Sync Options Explained](#sync-options-explained)
- [ignoreDifferences Explained](#ignoredifferences-explained)
- [RBAC Roles](#rbac-roles)
- [Useful Commands](#useful-commands)

---

## Directory Structure

```
argocd/
├── root-app.yaml               # Entrypoint — applied automatically by Terraform argocd-bootstrap module
│
├── config/                     # ArgoCD's own RBAC/projects/notifications config
│
├── projects/
│   └── platform.yaml           # AppProject: RBAC, allowed repos, allowed namespaces
│
└── applications/                     # Root App watches this directory
    ├── argocd-config.yaml            # Wave 0: ArgoCD's own configuration
    ├── platform-services.yaml        # Wave 1: Metrics Server, AWS LBC, Argo Rollouts
    ├── gatekeeper-install.yaml       # Wave 2: OPA Gatekeeper controller + CRDs
    ├── observability-crds.yaml       # Wave 3: Prometheus Operator CRDs
    ├── gatekeeper-templates.yaml     # Wave 4: Gatekeeper ConstraintTemplates
    ├── falco.yaml                    # Wave 4: Falco DaemonSet
    ├── gatekeeper-policies.yaml      # Wave 5: Gatekeeper Constraints (7 policies)
    ├── network-policies.yaml         # Wave 5: NetworkPolicies
    ├── observability.yaml            # Wave 6: kube-prometheus-stack
    └── online-boutique.yaml          # Wave 7: Online Boutique microservices
```

---

## How It Works

```
terraform apply
      │
      ├── EKS cluster provisioned
      │
      └── argocd-bootstrap module
            ├── Installs ArgoCD via Helm
            ├── Applies AppProject (projects/platform.yaml)
            └── Applies Root Application (root-app.yaml)
                        │
                        │  root-app watches argocd/applications/
                        │  and creates 10 child Applications
                        │
                        ├── Wave 0 ── argocd-config       →  argocd
                        │            ArgoCD's own RBAC/projects/notifications config
                        │
                        ├── Wave 1 ── platform-services   →  kube-system
                        │            Metrics Server, AWS Load Balancer Controller, Argo Rollouts
                        │            (ALB ready before Ingress resources are applied)
                        │
                        ├── Wave 2 ── gatekeeper-install  →  gatekeeper-system
                        │            OPA Gatekeeper controller + CRDs
                        │            (admission webhook active before later waves)
                        │
                        ├── Wave 3 ── observability-crds  →  monitoring
                        │            Prometheus Operator CRDs
                        │            (must exist before any ServiceMonitor/PrometheusRule)
                        │
                        ├── Wave 4 ── gatekeeper-templates →  gatekeeper-system
                        │            ConstraintTemplates registered as CRDs
                        │
                        ├── Wave 4 ── falco               →  falco
                        │            Falco (runtime threat detection)
                        │            (syncs in parallel with gatekeeper-templates)
                        │
                        ├── Wave 5 ── gatekeeper-policies →  gatekeeper-system
                        │            Constraints activate the 7 policies
                        │
                        ├── Wave 5 ── network-policies    →  online-boutique
                        │            NetworkPolicies
                        │            (syncs in parallel with gatekeeper-policies)
                        │
                        ├── Wave 6 ── observability       →  monitoring
                        │            Prometheus, Grafana, Alertmanager
                        │            (metrics scraped from wave 7 onward)
                        │
                        └── Wave 7 ── online-boutique     →  online-boutique
                                     11 microservices via Kustomize dev overlay
                                     frontend Ingress → LBC creates AWS ALB
```

ArgoCD polls the Git repository every 3 minutes and automatically applies any
change committed to `main`. `selfHeal: true` reverts any manual change made
directly to the cluster back to what is in Git.

---

## Getting Started

ArgoCD and the Root Application are bootstrapped automatically by the
`terraform/modules/argocd-bootstrap` module during `terraform apply`.
No manual steps are required after the infrastructure is provisioned.

After `terraform apply` completes, verify the platform is running:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region ap-southeast-1 --name eks-devsecops-dev-cluster

# Verify ArgoCD is running
kubectl get pods -n argocd

# Verify Root App was applied
kubectl get application root-app -n argocd

# Watch all 10 child Applications being created and synced, in wave order
kubectl get applications -n argocd -w

# Port-forward the ArgoCD UI
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

The Root App itself runs before all child Applications. When ArgoCD processes
`applications/`, it discovers the 10 child Application manifests and creates
them, each with its own sync-wave annotation — 10 Applications across 8 waves
(0–7); two waves (4 and 5) each hold a pair of Applications that don't depend
on one another.

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
| `destinations` | `argocd`, `kube-system`, `monitoring`, `gatekeeper-system`, `falco`, `online-boutique` | Deployments restricted to these namespaces |
| `clusterResourceWhitelist` | `*/*` | Allows cluster-scoped resources (CRDs, ClusterRoles, IngressClass) |
| `orphanedResources.warn` | `true` | ArgoCD warns if cluster has resources not tracked in Git |

**RBAC Roles defined in AppProject:**

| Role | Group | Permissions |
|---|---|---|
| `admin` | `platform-admins` | Full sync, create, delete on all Applications |
| `readonly` | `platform-viewers` | `get` only — read-only access to Application state |

---

## Child Applications

### argocd-config — Wave 0

**File:** `applications/argocd-config.yaml`

| Property | Value |
|---|---|
| Sync wave | `0` |
| Source path | `platform/gitops/argocd/config` |
| Destination namespace | `argocd` |
| Deploys | ArgoCD's own RBAC, AppProjects, and notification configuration |

**Why Wave 0 runs first:**

This Application manages ArgoCD's own configuration, so it must sync before
anything else — including before ArgoCD is asked to manage any other
platform resource. It's the only Application ArgoCD applies to itself.

---

### platform-services — Wave 1

**File:** `applications/platform-services.yaml`

| Property | Value |
|---|---|
| Sync wave | `1` |
| Source path | `platform/gitops/kustomize/platform-services` |
| Destination namespace | `kube-system` |
| Deploys | Metrics Server, AWS Load Balancer Controller, Argo Rollouts |

**Why Wave 1 runs early:**

The AWS Load Balancer Controller must be running before any `Ingress` resource
is applied. Without it, the `frontend` Ingress will stay in `Pending` indefinitely.
Metrics Server must be ready before any HPA depends on it, and Argo Rollouts
must be installed before the `online-boutique` Application (Wave 7) can create
`Rollout` resources.

**Dependency on Terraform:**
The LBC requires an IRSA role ARN injected into its Helm values:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "<terraform output -raw lbc_role_arn>"
```
This must be filled before pushing to Git.

---

### gatekeeper-install — Wave 2

**File:** `applications/gatekeeper-install.yaml`

| Property | Value |
|---|---|
| Sync wave | `2` |
| Source path | `platform/gitops/kustomize/security/opa-gatekeeper/install` |
| Destination namespace | `gatekeeper-system` |
| Deploys | OPA Gatekeeper controller + CRDs |

**Why Wave 2 runs before ConstraintTemplates and observability CRDs:**

The Gatekeeper controller and its CRDs must exist before any
`ConstraintTemplate` (Wave 4) or `Constraint` (Wave 5) resource can be applied.
Splitting the controller install from the templates and policies avoids a
race where a `ConstraintTemplate` is submitted before the CRD that defines it
is registered.

**`ignoreDifferences` configured for:**

```yaml
ignoreDifferences:
  - kind: ValidatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle   # injected at runtime by Gatekeeper
      - /webhooks/1/clientConfig/caBundle
  - kind: MutatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle
```

Gatekeeper injects its CA bundle into webhook configs at runtime. Without
`ignoreDifferences`, ArgoCD would see these as out-of-sync and loop trying
to revert them.

---

### observability-crds — Wave 3

**File:** `applications/observability-crds.yaml`

| Property | Value |
|---|---|
| Sync wave | `3` |
| Source path | `platform/gitops/kustomize/observability/crds` |
| Destination namespace | `monitoring` |
| Deploys | Prometheus Operator CRDs (`ServiceMonitor`, `PrometheusRule`, etc.) |

**Why Wave 3 is separate from the observability stack itself:**

The Prometheus Operator's own CRDs must be registered before the Helm release
in Wave 6 can create any `ServiceMonitor` or `PrometheusRule` resource.
Splitting CRDs into their own wave also lets other Applications (like
`gatekeeper-templates` and `falco` at Wave 4) proceed without waiting on the
full monitoring stack to be healthy.

---

### gatekeeper-templates — Wave 4

**File:** `applications/gatekeeper-templates.yaml`

| Property | Value |
|---|---|
| Sync wave | `4` |
| Source path | `platform/gitops/kustomize/security/opa-gatekeeper/install/templates` |
| Destination namespace | `gatekeeper-system` |
| Deploys | Gatekeeper ConstraintTemplates |

**Why Wave 4, after gatekeeper-install:**

ConstraintTemplates register custom policy types as CRDs, so the Gatekeeper
controller (Wave 2) must already be running. This Application syncs in
parallel with `falco`, since the two share no dependency on each other —
only on their respective prerequisite waves.

---

### falco — Wave 4

**File:** `applications/falco.yaml`

| Property | Value |
|---|---|
| Sync wave | `4` |
| Source path | `platform/gitops/kustomize/security/falco` |
| Destination namespace | `falco` |
| Deploys | Falco (runtime threat detection) |

**Why Wave 4, alongside gatekeeper-templates:**

Falco has no dependency on Gatekeeper or vice versa — both just need
`platform-services` (Wave 1) to be healthy. Placing them in the same wave
lets them sync concurrently instead of serializing unrelated work.

---

### gatekeeper-policies — Wave 5

**File:** `applications/gatekeeper-policies.yaml`

| Property | Value |
|---|---|
| Sync wave | `5` |
| Source path | `platform/gitops/kustomize/security/opa-gatekeeper/policies` |
| Destination namespace | `gatekeeper-system` |
| Deploys | Gatekeeper Constraints (7 policies) |

**Why Wave 5 runs after gatekeeper-templates:**

A `Constraint` instantiates a `ConstraintTemplate`, so the templates from
Wave 4 must already be registered as CRDs before any Constraint can be
created. Once this wave completes, every pod in later waves — including
`online-boutique` in Wave 7 — is validated at admission time against all
7 policies.

---

### network-policies — Wave 5

**File:** `applications/network-policies.yaml`

| Property | Value |
|---|---|
| Sync wave | `5` |
| Source path | `platform/gitops/kustomize/security/network-policies` |
| Destination namespace | `online-boutique` |
| Deploys | NetworkPolicies for the `online-boutique` namespace |

**Why Wave 5, alongside gatekeeper-policies:**

NetworkPolicies don't depend on Gatekeeper Constraints or vice versa, so the
two Applications sync in parallel. Both simply need the namespace and prior
waves' controllers to already be healthy.

---

### observability — Wave 6

**File:** `applications/observability.yaml`

| Property | Value |
|---|---|
| Sync wave | `6` |
| Source path | `platform/gitops/kustomize/observability/kube-prometheus-stack` |
| Destination namespace | `monitoring` |
| Deploys | Prometheus, Grafana, Alertmanager, Node Exporter, kube-state-metrics |

**Why Wave 6 runs after security and CRDs:**

The Prometheus Operator CRDs (Wave 3) must already exist, and Gatekeeper
policies (Wave 5) must be active so the Prometheus and Grafana pods are
validated against the same security constraints as all other workloads.

**`ServerSideApply: true`** is required because Prometheus Operator CRDs are
large and exceed the annotation size limit of client-side apply.

**`ignoreDifferences` configured for:**

```yaml
ignoreDifferences:
  - kind: StatefulSet
    jsonPointers:
      - /spec/volumeClaimTemplates   # Prometheus Operator patches this at runtime
  - kind: ServiceMonitor
    jsonPointers:
      - /spec/endpoints              # Operator normalises endpoint fields at runtime
```

Without these, ArgoCD would report the Application as `OutOfSync` on every
reconciliation loop due to fields mutated by the Prometheus Operator.

---

### online-boutique — Wave 7

**File:** `applications/online-boutique.yaml`

| Property | Value |
|---|---|
| Sync wave | `7` |
| Source path | `platform/gitops/kustomize/overlays/dev` |
| Destination namespace | `online-boutique` |
| Deploys | 11 microservices via Kustomize dev overlay |

**Why Wave 7 is last:**

All platform tools must be healthy before application workloads deploy:
- AWS LBC (Wave 1) must exist to handle the `frontend` Ingress → AWS ALB
- OPA Gatekeeper Constraints (Wave 5) must be enforcing policies before pods are admitted
- NetworkPolicies (Wave 5) must already be applied to the namespace
- Prometheus (Wave 6) ServiceMonitors must exist to start scraping from day one

**`PrunePropagationPolicy: foreground`** ensures that when a service is removed
from the Kustomize overlay, its pods are fully terminated before ArgoCD marks
the sync as complete — prevents ghost endpoints in the ALB target group.

---

## Sync Wave Order

```
Wave 0   argocd-config          ArgoCD's own RBAC/projects/notifications config applied
  │
Wave 1   platform-services      Metrics Server, AWS LBC, Argo Rollouts running and healthy
  │      └── prerequisite: LBC_ROLE_ARN in Helm values (from terraform output)
  │
Wave 2   gatekeeper-install     Gatekeeper controller + CRDs, admission webhook active
  │
Wave 3   observability-crds     Prometheus Operator CRDs registered
  │      └── required before any ServiceMonitor/PrometheusRule exists
  │
Wave 4   gatekeeper-templates   ConstraintTemplates registered as CRDs
Wave 4   falco                  Falco eBPF probes loaded, 10 custom rules active
  │      └── these two Applications sync in parallel — neither depends on the other
  │
Wave 5   gatekeeper-policies    Constraints activated — pods now validated against 7 policies
Wave 5   network-policies       NetworkPolicies applied in `online-boutique`
  │      └── these two Applications also sync in parallel
  │
Wave 6   observability          Prometheus scraping, Grafana dashboards live
  │      └── ServiceMonitors pick up online-boutique pods from Wave 7 onward
  │
Wave 7   online-boutique        11 microservices deployed, ALB provisioned by LBC
         └── loadgenerator initContainer waits for frontend to be Ready
```

ArgoCD will not start a wave until all Applications in the previous wave reach
`Healthy` status. Applications that share a wave number (4 and 5, above) sync
concurrently with each other, but still wait on the wave before them. If any
wave fails, later waves do not run.

---

## Sync Options Explained

All Applications share these `syncOptions`:

| Option | Effect |
|---|---|
| `CreateNamespace=true` | ArgoCD creates the destination namespace if it does not exist |
| `ApplyOutOfSyncOnly=true` | Only applies resources that are actually out of sync — reduces API server load and speeds up sync |
| `ServerSideApply=true` | Used on all 10 Applications — required for large CRDs (Gatekeeper, Prometheus Operator) that exceed client-side apply annotation limits |
| `PrunePropagationPolicy=foreground` | Used on `platform-services`, `network-policies`, `observability-crds`, `observability`, and `online-boutique` — waits for dependent resources to be deleted before marking prune complete |
| `RespectIgnoreDifferences=true` | Used on `gatekeeper-install` — respects `ignoreDifferences` during sync, not just during health checks |

---

## ignoreDifferences Explained

Some Kubernetes controllers mutate resources at runtime in ways that are not
reflected in Git. Without `ignoreDifferences`, ArgoCD would permanently report
these Applications as `OutOfSync`.

| Application | Resource | Field | Why it changes at runtime |
|---|---|---|---|
| `gatekeeper-install` | `ValidatingWebhookConfiguration` | `/webhooks/*/clientConfig/caBundle` | Gatekeeper injects CA bundle at startup |
| `gatekeeper-install` | `MutatingWebhookConfiguration` | `/webhooks/0/clientConfig/caBundle` | Same as above |
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
# Verify ArgoCD is running after terraform apply
kubectl get pods -n argocd

# Verify Root App was applied
kubectl get application root-app -n argocd

# Watch all 10 Applications and their sync status, in wave order
kubectl get applications -n argocd -w

# List sync-wave annotation for every Application (should read 0,1,2,3,4,4,5,5,6,7)
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}'

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080

# Get detailed status of a specific Application
argocd app get online-boutique

# Manually trigger a sync (skips the 3-minute poll interval)
argocd app sync root-app
argocd app sync argocd-config
argocd app sync platform-services
argocd app sync gatekeeper-install
argocd app sync observability-crds
argocd app sync gatekeeper-templates
argocd app sync falco
argocd app sync gatekeeper-policies
argocd app sync network-policies
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
```
