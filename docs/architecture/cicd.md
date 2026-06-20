# CI/CD Architecture

## Overview

The CI/CD system consists of five GitHub Actions workflows. Each workflow
has a single, well-defined responsibility. No workflow does everything —
concerns are separated across files to make each pipeline readable,
testable, and independently triggerable.

```
.github/workflows/
  terraform-ci.yaml     -- Static analysis on every PR touching IaC
  terraform-cd.yaml     -- Infrastructure provisioning (manual trigger)
  check-scan.yaml       -- Nightly deep security scan
  app-ci.yaml           -- Application security checks on every PR
  app-cd.yaml           -- Container build, scan, push, deploy (manual trigger)
```

---

## Workflow 1: Terraform CI (`terraform-ci.yaml`)

**Trigger:** Push to `develop` or `feature/**` + Pull Request targeting `develop`
**Purpose:** Catch Terraform errors and security misconfigurations before merge

```
validate
  |-- terraform fmt -check    (formatting enforced)
  |-- terraform init -backend=false
  |-- terraform validate
  |
  +-- [parallel] tflint       (naming conventions, unused declarations, AWS rules)
  +-- [parallel] tfsec        (security misconfiguration scanning)
  +-- [parallel] checkov      (CIS benchmark compliance, SARIF upload to Security tab)
  |
  v
ci-summary
  |-- PR comment with results table
  |-- GitHub Step Summary
  |-- Slack notification
```

**Key behaviors:**
- All scans run against `environments/dev/` with `-backend=false` — no AWS credentials required
- SARIF output from Checkov is uploaded to the GitHub Security tab automatically
- Feature branches use `soft_fail=true` for tfsec and Checkov — findings are reported but do not block
- `develop` branch and PRs use hard fail — findings block merge

---

## Workflow 2: Terraform CD (`terraform-cd.yaml`)

**Trigger:** `workflow_dispatch` only — never runs automatically
**Purpose:** Provision or destroy AWS infrastructure

```
plan | apply flow:
  plan --> opa-gate --> deploy --> notify-apply

destroy flow:
  destroy --> notify-destroy
```

**Plan job:**
- Authenticates to AWS via OIDC (no static keys)
- Runs `terraform plan -detailed-exitcode` against the real S3 backend
- Exports plan in two formats: binary (for apply) and JSON (for OPA evaluation)
- Uploads both as artifacts keyed by `github.sha`
- Exit code 0 = no changes, 2 = changes present, 1 = error

**OPA Gate job:**
- Downloads the JSON plan artifact
- Evaluates the plan against three policy files independently:
  - `security.rego` — EKS, ECR, IAM, SG rules
  - `networking.rego` — VPC, Subnet, NAT, ALB rules
  - `compliance.rego` — Tagging, encryption, backup rules
- Each policy runs as a separate step (fail fast on first violation)
- Warning violations are logged but do not block deployment
- Gate passes only when all deny violation counts equal zero

**Deploy job:**
- Downloads the approved binary plan artifact (same plan OPA evaluated)
- Applies exactly that plan — no risk of drift between plan and apply
- Captures `terraform output -json` and uploads as artifact
- Protected by `dev-apply` GitHub Environment (configure required reviewers here)

**Destroy job:**
- Runs independently — does not depend on plan or opa-gate
- Protected by `dev-destroy` GitHub Environment (required reviewers mandatory)
- Infrastructure destruction is never triggered automatically

**OIDC Authentication:**
No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` is stored anywhere.
The workflow assumes an IAM role via GitHub's OIDC token. The IAM role
trust policy restricts assumption to this specific repository and workflow.

---

## Workflow 3: Nightly Security Scan (`check-scan.yaml`)

**Trigger:** Scheduled (daily at 02:00 UTC+7) + `workflow_dispatch`
**Purpose:** Continuous security monitoring independent of code changes

Runs deeper scans than CI with stricter thresholds. Results are uploaded
as artifacts and posted to Slack. This workflow catches vulnerabilities
introduced by upstream dependency updates even when no code has changed.

---

## Workflow 4: Application CI (`app-ci.yaml`)

**Trigger:** Pull Request targeting `main` + `workflow_dispatch`
**Path filter:** `microservices-application/online-boutique/src/**`
**Purpose:** Validate application code security before merge

```
secret-scan
  |-- Gitleaks scans for credentials, tokens, private keys in the diff

build-check
  |-- Docker buildx builds the changed service image (does not push)
  |-- Validates that the Dockerfile builds successfully

trivy-scan
  |-- Scans the built image for CVEs
  |-- Reports HIGH and CRITICAL vulnerabilities as PR comment

opa-policy-test
  |-- Validates that Kubernetes manifests in kustomize/applications/
      comply with OPA policies before the image reaches the cluster

ci-summary
  |-- Aggregates results into PR comment and Slack notification
```

**Path filtering** ensures the CI pipeline only runs when application
source code changes. Infrastructure-only PRs do not trigger `app-ci`.

---

## Workflow 5: Application CD (`app-cd.yaml`)

**Trigger:** `workflow_dispatch` only
**Inputs:** `service` (dropdown of 13 services), `image_tag`, `environment`
**Purpose:** Build, scan, push, and deploy a specific microservice

```
build-push
  |-- Authenticate to ECR via OIDC
  |-- Docker buildx builds the service image
  |-- Tag: <account>.dkr.ecr.ap-southeast-1.amazonaws.com/eks-devsecops-dev/<service>:<tag>
  |-- Push to ECR

trivy-scan
  |-- Pull the pushed image by digest (immutable reference)
  |-- Scan for HIGH/CRITICAL CVEs
  |-- Fail if critical CVEs found (configurable threshold)

update-gitops
  |-- Run: kustomize edit set image <service>=<ecr-url>:<tag>
      in kustomize/overlays/dev/
  |-- Commit: "chore: update <service> image to <tag> [skip ci]"
  |-- Push to main

notify
  |-- Slack: service name, image tag, ECR URL, Trivy result, deploy status
```

**GitOps update mechanism:**
The CD pipeline does not directly call `kubectl` or ArgoCD APIs.
It pushes an image tag change to Git. ArgoCD detects the change
on its next polling cycle (within 3 minutes) and triggers a rolling
update. This preserves the GitOps contract — Git is always the
source of truth.

**`[skip ci]`** in the commit message prevents the CI pipeline from
triggering on the automated image tag update commit.

---

## Security Gates Summary

| Gate | Workflow | Blocks merge/deploy if |
|---|---|---|
| Gitleaks | app-ci | Credentials found in code |
| tfsec | terraform-ci | IaC security misconfigurations (hard fail on develop) |
| Checkov | terraform-ci | CIS compliance violations (hard fail on develop) |
| OPA Policy Gate | terraform-cd | Terraform plan violates security/networking/compliance policies |
| Trivy (CI) | app-ci | HIGH/CRITICAL CVEs in image build |
| Trivy (CD) | app-cd | CRITICAL CVEs in pushed ECR image |

---

## Concurrency Controls

Both CD workflows (`terraform-cd`, `app-cd`) use `concurrency` groups
with `cancel-in-progress: false`. This ensures:
- Only one Terraform apply runs at a time (prevents state corruption)
- A running apply is never cancelled mid-execution
- Subsequent runs queue rather than cancel the active run

---

## Artifact Retention

| Artifact | Workflow | Retention |
|---|---|---|
| `terraform-plan-<sha>` (binary + JSON) | terraform-cd | 5 days |
| `tflint-report` | terraform-ci | 7 days |
| `tfsec-report` | terraform-ci | 7 days |
| `checkov-report` (SARIF) | terraform-ci | 7 days |
| `tf-outputs-<sha>` | terraform-cd | 30 days |
| OPA report | terraform-cd | 7 days |

The binary plan artifact is retained for 5 days — long enough for the
apply to be triggered after a plan, but short enough to prevent stale
plans from being applied accidentally.
