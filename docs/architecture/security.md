# Security Architecture

## Defense-in-Depth Model

Security is applied in multiple independent layers. A threat that bypasses
one layer encounters the next. No single control is relied upon exclusively.

```
Layer 1: Development (shift-left)
  Gitleaks    -- secret scanning before code reaches GitHub
  tfsec       -- IaC misconfiguration detection on every PR
  Checkov     -- CIS compliance checks on Terraform code
  Trivy       -- container image vulnerability scanning before ECR push

Layer 2: Infrastructure
  Private subnets          -- worker nodes have no public IPs
  Security Groups          -- least-privilege network rules, SG-to-SG references
  IAM / IRSA               -- per-workload AWS identity, no shared credentials
  OIDC federation          -- no static AWS keys in CI/CD pipelines
  ECR repository policy    -- pull-only access for EKS nodes

Layer 3: Admission Control (OPA Gatekeeper)
  Intercepts every CREATE/UPDATE request to the Kubernetes API server
  Non-compliant resources are rejected before they are persisted
  7 ConstraintTemplates + 7 Constraints enforced cluster-wide

Layer 4: Runtime Detection (Falco)
  eBPF probes attached to kernel syscall events on every worker node
  10 custom rules covering MITRE ATT&CK tactics T1059 through T1543
  JSON output streamed to stdout for log aggregation

Layer 5: Observability
  Prometheus AlertManager firing on anomalous resource usage
  Grafana dashboards providing real-time visibility
  Operational runbooks defining response procedures
```

---

## OPA Gatekeeper — Admission Control

Gatekeeper installs a `ValidatingWebhookConfiguration` that registers
a webhook with the Kubernetes API server. Every admission request for
a `CREATE` or `UPDATE` operation is sent to the Gatekeeper controller
before the resource is persisted to etcd.

### Policy Architecture

```
ConstraintTemplate (Wave 1)
  Registers a new CRD kind (e.g. K8sRequiredLabels)
  Contains Rego policy logic
  Applied to: all namespaces via ArgoCD

Constraint (Wave 2)
  Instance of a ConstraintTemplate
  Specifies which namespaces and resource kinds to enforce against
  Contains parameters (e.g. which labels to require)
  Applied AFTER ConstraintTemplates — CRD must exist before instance
```

### Enforced Policies (7 constraints)

| Constraint | Template Kind | Scope | Blocks |
|---|---|---|---|
| require-labels | K8sRequiredLabels | online-boutique Pods | Pods without `app` label |
| require-resource-limits | K8sRequiredResources | All Pods | Containers without CPU and memory limits |
| require-non-root | K8sRequireNonRoot | All Pods | Containers without `runAsNonRoot: true` |
| disallow-privileged | K8sBlockPrivileged | All Pods | `securityContext.privileged: true` |
| disallow-latest-tag | K8sDisallowedTags | All Pods | Images tagged `:latest` |
| require-readonly-rootfs | K8sReadOnlyRootFS | All Pods | Containers without `readOnlyRootFilesystem: true` |
| allow-ecr-only | K8sAllowedRepos | All Pods | Images not from ECR or approved registries |

### Excluded Namespaces

The following namespaces are excluded from constraint enforcement
because they contain system workloads that require elevated privileges:

- `kube-system` — EKS system components (node-exporter, kube-proxy)
- `gatekeeper-system` — Gatekeeper must exempt itself
- `falco` — Falco DaemonSet requires `privileged: true` for eBPF
- `argocd` — ArgoCD controller requires elevated permissions
- `monitoring` — Prometheus node-exporter requires host-level access

### Why OPA is Deployed Before Applications (Wave 2 before Wave 4)

If Gatekeeper were deployed after Online Boutique, the microservice pods
would have been admitted without any policy validation. A later Gatekeeper
deployment would audit existing resources but could not retroactively
block already-running non-compliant pods without disruption.

By enforcing Wave 2 before Wave 4, every Online Boutique pod is
validated at admission time. The cluster never contains non-compliant
running workloads.

---

## Falco — Runtime Threat Detection

Falco attaches eBPF probes to kernel syscall events using the modern eBPF
driver (no kernel module required). Every syscall on every worker node
is evaluated against the rule engine in real time.

### Detection Architecture

```
Kernel syscall events
  |
  v
eBPF probe (attached by Falco DaemonSet on each node)
  |
  v
Rule engine (evaluates event against all loaded rules)
  |
  +-- Rule matches: emit JSON event to stdout
  +-- No match: discard event
  |
  v
Container stdout -> Kubernetes log aggregation -> CloudWatch
```

### Custom Rules Structure

Rules are stored in a ConfigMap (`falco-custom-rules`) mounted into
each Falco pod at `/etc/falco/custom-rules/custom-rules.yaml`. Falco
monitors this file via `inotify` and hot-reloads rules when the
ConfigMap changes — no pod restart or Helm upgrade required.

This architecture separates rule management (frequent, low-risk changes)
from Falco configuration (rare, higher-risk changes).

### MITRE ATT&CK Coverage

| Rule | MITRE Tactic | Technique |
|---|---|---|
| Shell Spawned in Container | Execution | T1059 |
| Package Manager Execution | Persistence | T1546 |
| Sensitive File Read | Credential Access | T1552 |
| Unexpected Outbound Connection | Exfiltration | T1048 |
| Write Below Binary Directory | Persistence | T1574 |
| Unexpected Container in Namespace | Initial Access | T1190 |
| Setuid/Setgid Bit Set | Privilege Escalation | T1548 |
| Cryptomining Process | Impact | T1496 |
| Service Account Token Write | Credential Access | T1528 |
| Drift — New Binary Executed | Persistence | T1543 |

### OPA vs Falco — Complementary Controls

```
OPA Gatekeeper                    Falco
|                                 |
| Operates at: admission time     | Operates at: runtime
| Sees: desired state (manifest)  | Sees: actual behavior (syscalls)
| Can: block non-compliant pods   | Can: detect attacks against running pods
| Cannot: see runtime behavior    | Cannot: prevent a pod from starting
|                                 |
| Example: blocks a Deployment    | Example: detects if a running container
|   with privileged: true         |   spawns a shell after exploitation
```

---

## Container Security Baseline

Every Online Boutique container runs with the following security context:

```yaml
securityContext:
  runAsNonRoot: true              # cannot run as root
  runAsUser: 1000                 # specific non-root UID
  allowPrivilegeEscalation: false # cannot gain more privileges than parent
  readOnlyRootFilesystem: true    # cannot write to container filesystem
  capabilities:
    drop: [ALL]                   # all Linux capabilities dropped
```

This baseline is enforced at two levels:
1. **Declared** in each Deployment manifest (platform convention)
2. **Enforced** by OPA Gatekeeper constraints at admission time

A pod that declares an insecure context is rejected by the webhook
before the scheduler ever sees it.

---

## Secret Management

| Secret type | Where stored | How accessed |
|---|---|---|
| AWS credentials (CI/CD) | GitHub OIDC federation | Role assumption via short-lived token |
| RDS password | GitHub Secret (`TF_VAR_DB_PASSWORD`) | Injected as env var at Terraform apply time |
| Slack webhook | GitHub Secret (`SLACK_WEBHOOK_URL`) | Injected into workflow env |
| ArgoCD admin password | Helm values (hashed) | ArgoCD generates bcrypt hash at install |
| Grafana admin password | Helm values | Plaintext in dev; External Secrets in prod |

**Future improvement:** External Secrets Operator + AWS Secrets Manager
integration is listed in the roadmap. This would eliminate all plaintext
secrets from Helm values files and replace them with `ExternalSecret`
resources that pull values from Secrets Manager at runtime.

---

## Network Security

All inter-service communication within the cluster uses Kubernetes
ClusterIP Services — no service is directly reachable from the internet
except the frontend via the ALB.

The ALB Security Group allows inbound 80/443 from `0.0.0.0/0`.
The EKS Nodes Security Group allows inbound on NodePort range (30000-32767)
only from the ALB Security Group. RDS is reachable only from the EKS
Nodes Security Group on port 5432.

No security group rule uses `0.0.0.0/0` as the source for anything
other than the public-facing ALB ingress rules.
