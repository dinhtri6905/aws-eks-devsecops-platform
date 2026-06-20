# GitOps Architecture

## What GitOps Means Here

GitOps is an operational model where Git is the single source of truth
for the desired state of the cluster. Every resource in the cluster —
from Helm chart values to pod replicas — is declared in a Git repository.
ArgoCD continuously reconciles the actual state of the cluster against
what is declared in Git.

The practical consequences:
- No engineer runs `kubectl apply` directly after initial bootstrap
- Every change is reviewed via Pull Request before reaching the cluster
- Drift (manual cluster changes) is automatically reverted by ArgoCD
- Rollback is a `git revert` followed by a push

---

## App of Apps Pattern

A single Root Application watches one directory in Git. That directory
contains child Application manifests. When the Root App syncs, it
creates, updates, or deletes child Applications based on what files exist.

```
Root Application (root-app.yaml)
  Watches: platform/gitops/argocd/applications/
  Creates:
    platform-services  (wave 1)
    security           (wave 2)
    observability      (wave 3)
    online-boutique    (wave 4)
```

This pattern means adding a new platform tool is as simple as creating
a new Application manifest file in `argocd/applications/`. The Root App
picks it up on the next sync cycle.

See [ADR-002](decisions/ADR-002-app-of-apps.md) for the rationale
behind this pattern.

---

## Sync Wave Ordering

ArgoCD sync waves control the deployment order within a single sync
operation. Resources with a lower wave number are applied and must
become healthy before higher-numbered waves begin.

```
Wave 0   root-app
  Created by Terraform argocd-bootstrap module.
  Discovers all child Applications.

Wave 1   platform-services
  Deploys: Metrics Server, AWS Load Balancer Controller
  Prerequisite for: all Ingress resources (ALB must exist first)
  Prerequisite for: HPA (Metrics Server must exist first)

Wave 2   security
  Deploys: OPA Gatekeeper, Falco
  Gatekeeper webhook becomes active at this point.
  Every pod created from this wave onward is validated at admission.
  Falco eBPF probes are loaded on all worker nodes.

Wave 3   observability
  Deploys: kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
  ServiceMonitors are created here — they immediately start scraping
  wave 4 pods as soon as they are created.

Wave 4   online-boutique
  Deploys: 13 microservices via Kustomize dev overlay
  frontend Ingress triggers ALB creation via LBC (wave 1 dependency)
  All pods are validated by Gatekeeper (wave 2 dependency)
  All pods are immediately scraped by Prometheus (wave 3 dependency)
```

**Critical dependency: Wave 2 before Wave 4.** If OPA Gatekeeper is
not deployed before Online Boutique, the microservice pods would be
admitted without policy validation. Deploying security before the
application layer is a deliberate architectural choice — not just
a convenience.

---

## Kustomize Architecture

Kustomize provides a way to maintain a single base configuration and
apply environment-specific patches on top. The platform uses Kustomize
for the Online Boutique application layer.

```
kustomize/
  base/online-boutique/        # Canonical manifests for all 13 services
    |
    +-- overlays/dev/          # Patches: replicas=1, env=dev
    +-- overlays/prod/         # Patches: replicas=2, HPA, higher limits
```

Platform tools (LBC, Gatekeeper, Falco, Prometheus) use Helm charts
referenced directly in ArgoCD Application sources. Kustomize is reserved
for the application layer where environment differences are meaningful.

See [ADR-003](decisions/ADR-003-kustomize-vs-helm.md) for the rationale.

---

## Helm Chart Integration

ArgoCD Applications that deploy Helm charts use the `helmCharts:` block
in `kustomization.yaml`. Values are stored in `values.yaml` files
alongside the kustomization, making them version-controlled and
diff-able in Pull Requests.

Example from `security/opa-gatekeeper/kustomization.yaml`:
```yaml
helmCharts:
  - name: gatekeeper
    repo: https://open-policy-agent.github.io/gatekeeper/charts
    version: 3.17.1
    releaseName: gatekeeper
    namespace: gatekeeper-system
    valuesFile: values.yaml
```

This approach allows combining Helm chart deployment with additional
Kubernetes resources (ConstraintTemplates, Constraints, ConfigMaps)
in a single ArgoCD Application sync.

---

## ignoreDifferences Configuration

Some Kubernetes controllers mutate resources at runtime in ways that
are not reflected in Git. Without `ignoreDifferences` configuration,
ArgoCD would permanently report these Applications as `OutOfSync` and
attempt to revert the controller's changes on every reconciliation.

| Application | Resource | Field | Why it changes |
|---|---|---|---|
| security | ValidatingWebhookConfiguration | caBundle | Gatekeeper injects its CA at startup |
| security | MutatingWebhookConfiguration | caBundle | Same |
| observability | StatefulSet | volumeClaimTemplates | Prometheus Operator patches this at runtime |
| observability | ServiceMonitor | endpoints | Prometheus Operator normalises fields |

---

## Self-Healing and Drift Detection

ArgoCD polls the Git repository every 3 minutes. When it detects a
difference between the desired state (Git) and the actual state
(cluster), it takes one of two actions:

- **AutoSync disabled:** marks the Application as `OutOfSync`, waits
  for a human to approve the sync
- **AutoSync enabled (`selfHeal: true`):** immediately applies the
  desired state, reverting any drift

All Applications in this platform use `selfHeal: true`. This means
if an engineer manually edits a Deployment directly on the cluster,
ArgoCD will revert the change within 3 minutes.

This behavior is intentional and enforces the GitOps contract.

---

## Git Push to Deployment Flow

```
Developer pushes code change to a feature branch
  |
  v
Pull Request created against develop
  |
  v
GitHub Actions: Terraform CI (if infra change)
  validate -> tflint -> tfsec -> checkov -> ci-summary
  |
  v
Code review and approval
  |
  v
Merge to main / develop
  |
  v (application change)
GitHub Actions: app-cd (workflow_dispatch)
  build image -> trivy scan -> push to ECR -> update kustomize image tag -> push to Git
  |
  v
ArgoCD detects image tag change in Git (within 3 minutes)
  |
  v
ArgoCD syncs online-boutique Application
  |
  v
Kubernetes rolling update: old pods terminated, new pods started
  |
  v
OPA Gatekeeper validates new pods at admission
  |
  v
Prometheus begins scraping new pods immediately
  |
  v
Deployment complete
```
