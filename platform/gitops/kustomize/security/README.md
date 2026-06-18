# platform/gitops/kustomize/security

Security layer for the Cloud-Native Secure GitOps Platform on AWS EKS.

This directory contains Policy-as-Code enforcement via OPA Gatekeeper and
runtime threat detection via Falco. Both tools are deployed as Wave 1 in the
ArgoCD App-of-Apps pipeline — after platform services (Wave 0) but before
observability (Wave 2) and applications (Wave 3), ensuring all policies are
active before any workload reaches the cluster.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [How It Works](#how-it-works)
- [OPA Gatekeeper](#opa-gatekeeper)
  - [How Policies Are Structured](#how-policies-are-structured)
  - [ConstraintTemplates](#constrainttemplates-7-policies)
  - [Constraints](#constraints-7-active-policies)
  - [Excluded Namespaces](#excluded-namespaces)
  - [Sync Wave Order](#sync-wave-order)
  - [Viewing Violations](#viewing-violations)
- [Falco](#falco)
  - [Architecture](#architecture)
  - [Rule Update Path](#rule-update-path)
  - [Custom Rules](#custom-rules-10-rules)
  - [Viewing Falco Events](#viewing-falco-events)
- [Security Layer Interaction](#security-layer-interaction)
- [Useful Commands](#useful-commands)

---

## Directory Structure

```
security/
├── kustomization.yaml              # Root aggregator — references opa-gatekeeper and falco
│
├── opa-gatekeeper/                 # Policy-as-Code admission control
│   ├── kustomization.yaml          # helmCharts + ConstraintTemplates + Constraints
│   ├── values.yaml                 # Helm values for the Gatekeeper controller
│   │
│   ├── templates/                  # ConstraintTemplate CRDs (Wave 1)
│   │   ├── kustomization.yaml
│   │   ├── k8srequiredlabels.yaml
│   │   ├── k8srequiredresources.yaml
│   │   ├── k8snonroot.yaml
│   │   ├── k8sdisallowprivileged.yaml
│   │   ├── k8sdisallowedtags.yaml
│   │   ├── k8sreadonlyrootfs.yaml
│   │   └── k8sallowedrepos.yaml
│   │
│   └── constraints/                # Constraint instances (Wave 2)
│       ├── kustomization.yaml
│       ├── require-labels.yaml
│       ├── require-resource-limits.yaml
│       ├── require-non-root.yaml
│       ├── disallow-privileged.yaml
│       ├── disallow-latest-tag.yaml
│       ├── require-read-only-root-filesystem.yaml
│       └── allow-ecr-and-trusted-registries-only.yaml
│
└── falco/                          # Runtime threat detection
    ├── kustomization.yaml          # helmCharts + ConfigMap reference
    ├── values.yaml                 # Helm values — extraVolumes for rules mount
    └── custom-rules/
        ├── kustomization.yaml
        └── custom-rules.yaml       # ConfigMap with 10 custom detection rules
```

---

## How It Works

```
ArgoCD syncs security Application (sync-wave: "2")
│
│  OPA Gatekeeper
│  ├── Wave 0 — Helm chart installs controller + ValidatingWebhookConfiguration
│  │           Webhook intercepts all CREATE/UPDATE requests to the API server
│  ├── Wave 1 — ConstraintTemplates register 7 custom policy CRDs
│  └── Wave 2 — Constraints activate policies against specific namespaces
│
│  Falco
│  ├── Wave 0 — Helm chart deploys DaemonSet on every worker node
│  │           eBPF probes attach to kernel syscall events
│  └── Wave 1 — ConfigMap (custom-rules) mounted at /etc/falco/custom-rules/
│               Falco hot-reloads rules via inotify — no pod restart needed
│
└── Any Pod created after this point is validated by both tools
```

---

## OPA Gatekeeper

OPA Gatekeeper runs a `ValidatingWebhookConfiguration` that intercepts every
`CREATE` and `UPDATE` request to the Kubernetes API server. Non-compliant
resources are rejected before they are persisted — nothing reaches etcd.

### How Policies Are Structured

```
ConstraintTemplate   →   defines a policy type (registers a new CRD)
Constraint           →   activates that policy against specific namespaces/kinds
```

This two-layer design allows the same policy logic (e.g. "require labels") to be
applied differently across environments by writing different Constraint instances.

### ConstraintTemplates (7 policies)

| File | Kind | What it enforces |
|---|---|---|
| `k8srequiredlabels.yaml` | `K8sRequiredLabels` | Required labels must be present with values matching a regex |
| `k8srequiredresources.yaml` | `K8sRequiredResources` | All containers must declare CPU and memory requests and limits |
| `k8snonroot.yaml` | `K8sRequireNonRoot` | `runAsNonRoot: true` must be set at pod or container level |
| `k8sdisallowprivileged.yaml` | `K8sBlockPrivileged` | `securityContext.privileged: true` is blocked |
| `k8sdisallowedtags.yaml` | `K8sDisallowedTags` | Image tags in the disallowed list (`:latest`) are rejected |
| `k8sreadonlyrootfs.yaml` | `K8sReadOnlyRootFS` | `readOnlyRootFilesystem: true` must be set |
| `k8sallowedrepos.yaml` | `K8sAllowedRepos` | Images must come from an allowed registry prefix |

All ConstraintTemplates carry `argocd.argoproj.io/sync-wave: "1"` so they are
applied before their corresponding Constraints.

### Constraints (7 active policies)

| File | Kind | Scope | Key config |
|---|---|---|---|
| `require-labels.yaml` | `K8sRequiredLabels` | `online-boutique` Pods | Requires `app` label matching `^[a-z0-9-]+$` |
| `require-resource-limits.yaml` | `K8sRequiredResources` | All Pods except system namespaces | Requires `cpu` and `memory` requests and limits |
| `require-non-root.yaml` | `K8sRequireNonRoot` | All Pods except system namespaces | `runAsNonRoot: true` |
| `disallow-privileged.yaml` | `K8sBlockPrivileged` | All Pods except system namespaces | Blocks `privileged: true` |
| `disallow-latest-tag.yaml` | `K8sDisallowedTags` | All Pods except system namespaces | Blocks `:latest` tag |
| `require-read-only-root-filesystem.yaml` | `K8sReadOnlyRootFS` | All Pods except system namespaces | `readOnlyRootFilesystem: true` |
| `allow-ecr-and-trusted-registries-only.yaml` | `K8sAllowedRepos` | All Pods except system namespaces | Only ECR + trusted public registries |

### Excluded Namespaces

All Constraints exclude the following namespaces from enforcement:

```
kube-system       — EKS system components may need privileged access
gatekeeper-system — Gatekeeper must be exempt to manage itself
falco             — Falco DaemonSet requires privileged: true for eBPF
argocd            — ArgoCD controller uses various system-level permissions
monitoring        — Prometheus node-exporter requires host-level access
```

### Sync Wave Order

```
Wave 0 — Gatekeeper Helm chart   →  controller + webhook running
Wave 1 — ConstraintTemplates     →  7 new CRDs registered in API server
Wave 2 — Constraints             →  policies active, admission webhook enforcing
```

Constraints must be applied after ConstraintTemplates — if a Constraint is
applied before its ConstraintTemplate CRD exists, the API server will reject it.

### Viewing Violations

```bash
# List all constraint violations across the cluster
kubectl get constraints

# Detailed view of a specific constraint
kubectl describe k8srequiredresources require-resource-requests-limits

# All violations for a specific constraint kind
kubectl get k8srequiredlabels -o yaml
```

---

## Falco

Falco runs as a DaemonSet on every EKS worker node using the modern eBPF driver.
It attaches probes to kernel syscall events and evaluates them against detection
rules at runtime — threats are detected while they are happening, not after.

### Architecture

```
Worker Node
│
├── Falco DaemonSet pod
│   ├── eBPF probe  →  reads kernel syscall events
│   ├── Rule engine →  evaluates events against rules
│   └── Output      →  JSON logs → stdout → CloudWatch (via node agent)
│
└── Custom rules ConfigMap
    └── Mounted at /etc/falco/custom-rules/custom-rules.yaml
        Falco watches via inotify — rule changes take effect without restart
```

### Rule Update Path

```
Edit custom-rules/custom-rules.yaml
      │
      └── git push → ArgoCD detects ConfigMap diff → apply ConfigMap only
                          │
                          └── Kubernetes updates volume mount on each node
                                    │
                                    └── Falco inotify → reload rules
                                        (no pod restart, no Helm upgrade)
```

This is the key advantage of the tách file approach — Helm upgrades are only
needed when changing Falco configuration (`values.yaml`), not when tuning rules.

### Custom Rules (10 rules)

| Rule | Priority | MITRE Tactic | What triggers it |
|---|---|---|---|
| Shell Spawned in Container | CRITICAL | T1059 Execution | Any shell binary spawned inside a microservice pod |
| Package Manager Execution | WARNING | T1546 Persistence | `apt`, `apk`, `pip`, `npm` etc. run inside a container |
| Sensitive File Read | CRITICAL | T1552 Credential Access | Read attempt on `~/.kube`, `~/.aws`, `/etc/shadow`, SA token path |
| Unexpected Outbound Connection | NOTICE | T1048 Exfiltration | Outbound connection on a port not in the approved service list |
| Write Below Binary Directory | CRITICAL | T1574 Persistence | File written to `/bin`, `/sbin`, `/usr/bin`, `/usr/local/bin` |
| Unexpected Container in Namespace | WARNING | T1190 Initial Access | Container name not in the approved microservice list |
| Setuid/Setgid Bit Set | CRITICAL | T1548 Privilege Escalation | `chmod` with `S_ISUID` or `S_ISGID` flag |
| Cryptomining Process | CRITICAL | T1496 Impact | `xmrig`, `minerd`, `ethminer` or similar process names |
| Service Account Token Write | CRITICAL | T1528 Credential Access | Write to `/var/run/secrets/kubernetes.io/serviceaccount` |
| Drift — New Binary Executed | WARNING | T1543 Persistence | Executable written after container start (`proc.is_exe_writable`) |

All rules are scoped to the `online-boutique` namespace via the
`in_boutique_namespace` macro.

### Viewing Falco Events

```bash
# Stream live security events from all Falco pods
kubectl logs -l app.kubernetes.io/name=falco -n falco -f

# Filter by priority
kubectl logs -l app.kubernetes.io/name=falco -n falco | grep '"priority":"CRITICAL"'

# Count events by rule
kubectl logs -l app.kubernetes.io/name=falco -n falco \
  | jq -r '.rule' | sort | uniq -c | sort -rn
```

---

## Security Layer Interaction

OPA Gatekeeper and Falco complement each other at different points in the
attack timeline:

```
Before admission (OPA Gatekeeper)
│
│  Developer pushes bad manifest → ArgoCD tries to apply it
│  → Webhook intercepts API call → Rego policy evaluates → DENY
│  → Bad pod never starts
│
│  Example: deployment with privileged: true → blocked by disallow-privileged.yaml
│
└──────────────────────────────────────────────────────────────────

After admission (Falco)
│
│  Pod is running (passed all policies at admission time)
│  → Attacker exploits app vulnerability → shell spawned in container
│  → Falco eBPF probe detects execve syscall → rule matches → ALERT
│  → JSON event emitted → CloudWatch / SIEM → incident response
│
└──────────────────────────────────────────────────────────────────
```

Neither tool replaces the other. Gatekeeper prevents misconfiguration from ever
reaching the cluster. Falco catches attacks against workloads that are already
running and compliant with all policies.

---

## Useful Commands

```bash
# Check Gatekeeper controller health
kubectl get pods -n gatekeeper-system

# List all active constraints
kubectl get constraints

# Check audit results (violations on existing resources)
kubectl get k8srequiredresources require-resource-requests-limits -o jsonpath='{.status.violations}' | jq .

# View Falco DaemonSet status
kubectl get daemonset -n falco

# Verify custom rules ConfigMap is mounted
kubectl exec -n falco ds/falco -- cat /etc/falco/custom-rules/custom-rules.yaml | head -20

# Live Falco event stream
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 -f

# Test a policy manually (dry-run)
kubectl run test-pod --image=nginx:latest --dry-run=server -n online-boutique
# Expected: admission webhook should deny ":latest" tag
```
