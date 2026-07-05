# CI/CD Pipelines & OPA Policies

Reference documentation for the GitHub Actions automation layer and the OPA policy enforcement layer of the **Cloud-Native Secure GitOps Platform on AWS EKS**.

---

## Table of Contents

- [Repository Layout](#repository-layout)
- [End-to-End Flow](#end-to-end-flow)
- [GitHub Actions Workflows](#github-actions-workflows)
  - [terraform-ci.yaml](#terraform-ciyaml)
  - [terraform-cd.yaml](#terraform-cdyaml)
  - [check-scan.yaml](#check-scanyaml)
  - [app-ci.yaml](#app-ciyaml)
  - [app-cd.yaml](#app-cdyaml)
- [OPA Policies](#opa-policies)
  - [security.rego](#securityrego)
  - [networking.rego](#networkingreogo)
  - [compliance.rego](#compliancerego)
- [GitHub Secrets — Setup Guide](#github-secrets--setup-guide)
- [GitHub Environments — Setup Guide](#github-environments--setup-guide)

---

## Repository Layout

```text
.github/
└── workflows/
    ├── terraform-ci.yaml   # Terraform static analysis: fmt / validate / tflint / tfsec / checkov
    ├── terraform-cd.yaml   # Terraform delivery: plan → OPA gate → apply / destroy
    ├── check-scan.yaml     # On-demand security scan: OPA full (3 policies) + tfsec deep scan
    ├── app-ci.yaml         # Application CI: gitleaks / kustomize validate / OPA k8s / falco / trivy fs
    └── app-cd.yaml         # Application CD: build → Trivy image scan → push ECR → update Kustomize → commit

platform/infrastructure/terraform/
├── environments/dev/       # TF_WORKING_DIR used by terraform-ci, terraform-cd, check-scan
├── modules/
└── policies/
    ├── security.rego       # package data.terraform.security
    ├── networking.rego     # package data.terraform.networking
    └── compliance.rego     # package data.terraform.compliance

platform/security/
├── opa/                    # OPA unit tests for K8s admission (used by app-ci: opa-k8s-policies)
└── falco/                  # Falco rules (*.yaml/*.yml), validated by app-ci: falco-validate

platform/gitops/
├── scripts/Render-LbcValues.ps1
├── kustomize/
│   ├── platform-services/aws-load-balancer-controller/values.yaml (+ values.rendered.yaml)
│   ├── platform-services/, security/, observability/, applications/online-boutique/   # built by app-ci: kustomize-validate
│   └── overlays/dev/applications/online-boutique/kustomization.yaml   # updated by app-cd: update-gitops

microservices-application/
└── <service>/Dockerfile    # built by app-cd: build-and-scan (matrix per service)
```

---

## End-to-End Flow

```text
terraform-ci.yaml
  (push develop/feature/** or PR → develop, paths: environments/dev/**, modules/**, policies/**)
          │
          ▼
 validate ──► tflint ──┐
          ├──► tfsec   ├──► ci-summary → PR comment + Slack
          └──► checkov ┘

terraform-cd.yaml (workflow_dispatch: action = plan/apply/destroy)
   plan ──► opa-gate (security + networking + compliance .rego) ──► apply
                │ deny > 0                                            │
                └──► notify-opa-deny (Slack)          render LBC values → commit [skip ci]
                                                                        │
                                                                        ▼
                                                               notify-apply (Slack)

app-ci.yaml (workflow_dispatch)
   gitleaks ──► kustomize-validate ─┐
            ├──► opa-k8s-policies    ├──► app-ci-summary → Step Summary + PR comment + Slack
            ├──► falco-validate      │
            └──► trivy-filesystem   ─┘
          │
          ▼
 app-cd.yaml (workflow_dispatch, optional service input)
   detect-changes ──► build-and-scan (matrix, fail-fast:false, Trivy image scan blocks CRITICAL)
                              │
                              ▼
                     update-gitops (only updates services with status=success)
                              │
                              ▼
                     kustomization.yaml committed to main → ArgoCD auto-syncs

check-scan.yaml (workflow_dispatch: scan_type = all/opa-only/tfsec-only)
   opa-full-scan (3 policies: deny + warn) ──┐
   tfsec-deep (full ruleset)                 ├──► generate-reports → Step Summary + Slack
```

---

## GitHub Actions Workflows

### terraform-ci.yaml

**Trigger:** `push` to `develop` / `feature/**`, `pull_request` → `develop`, and `workflow_dispatch` (input `scan_type`: `all`/`validate`/`tflint`/`tfsec`/`checkov`). Only triggers when changes fall under `platform/infrastructure/terraform/environments/dev/**`, `.../modules/**`, `.../policies/**`, or the workflow file itself.

**Purpose:** Static analysis gate that runs before any infrastructure change reaches a plan or apply.

**Job flow:**

```text
validate ─┐
tflint    ├──► ci-summary → PR comment + Slack
tfsec     │
checkov   ┘
```

`tflint`, `tfsec`, and `checkov` all `needs: validate` and then run in parallel.

| Job | Tool | Notes |
|---|---|---|
| `validate` | `terraform fmt -check -recursive -diff` + `terraform init -backend=false` + `terraform validate` | Comments the result on the PR |
| `tflint` | TFLint + AWS plugin `0.30.0` | Rules: naming convention, required providers/version, unused declarations, documented variables/outputs. Exports JSON as artifact `tflint-report`, comments the first 10 issues on the PR |
| `tfsec` | `aquasecurity/tfsec-action@v1.0.0` + a second Docker-based run for JSON | `soft_fail` = `true` on `feature/**` branches, `false` on other branches. Artifact `tfsec-report` |
| `checkov` | `bridgecrewio/checkov-action@master`, SARIF output | Skips checks `CKV_AWS_8`, `CKV2_AWS_12`. SARIF uploaded to **Security → Code scanning alerts** (category `Checkov-Terraform-DEV`), artifact `checkov-report`, comments the first 8 HIGH/CRITICAL issues on the PR |
| `ci-summary` | — | `needs` all 4 jobs above, `if: always()`. Downloads all artifacts, writes the Step Summary, posts a combined PR comment, notifies Slack |

**Required secrets:** `SLACK_WEBHOOK_URL`

---

### terraform-cd.yaml

**Trigger:** `workflow_dispatch` only, with inputs `action` (`plan`/`apply`/`destroy`, default `plan`) and `environment` (`dev`, default `dev`, currently the only option).

**Concurrency:** `group: terraform-cd-<environment>`, `cancel-in-progress: false` — only one CD run at a time.

**Purpose:** Policy-gated infrastructure delivery — an OPA evaluation step sits between `plan` and `apply`; no infrastructure change is applied without passing all three policy files.

**Job flow:**

```text
plan ──► opa-gate ──► apply ──► notify-apply
              │
              └──► notify-opa-deny (if opa-gate fails)

destroy (manual dispatch only, action=destroy) ──► notify-destroy
```

| Job | Description |
|---|---|
| `plan` | Environment `dev-plan`. Authenticates to AWS via OIDC. `terraform init` against the S3 backend (`BUCKET_TF_STATE`). `terraform plan -out=tfplan -detailed-exitcode` (0 = no changes, 2 = changes present, 1 = error). Exports the plan as JSON (`terraform show -json`), uploads artifact `terraform-plan-<run_id>` containing `tfplan` + `tf-plan.json` + `tf-plan.txt`. |
| `opa-gate` | Only runs when `plan_exitcode == '2'`. Downloads the plan artifact, installs the OPA CLI, runs `opa eval` against `security.rego`, `networking.rego`, and `compliance.rego` — both `deny` and `warn` rules. Total `deny` count > 0 fails the job (blocking apply); `warn` is logged only. |
| `apply` | `needs: [plan, opa-gate]`. Environment `dev-apply`. Runs when `opa-gate` succeeds, `plan_exitcode == '2'`, and `workflow_dispatch action=apply`. Applies the exact `tfplan` file already reviewed by OPA (no re-plan). Afterward collects `terraform output -json`, renders AWS Load Balancer Controller values via `Render-LbcValues.ps1`, and commits `values.rendered.yaml` as `github-actions[bot]` (message `[skip ci]`). |
| `notify-apply` | `needs: apply`, `if: always() && needs.apply.result != 'skipped'` — notifies Slack with the apply result. |
| `destroy` | Environment `dev-destroy`. Runs only when `workflow_dispatch action=destroy`. `terraform destroy -auto-approve`. |
| `notify-destroy` | `needs: destroy` — notifies Slack (`warning` on success, `danger` on failure). |

**Required secrets:** `AWS_DEV_ROLE_ARN`, `BUCKET_TF_STATE`, `GITOPS_REPO_URL`, `SLACK_WEBHOOK_URL`

---

### check-scan.yaml

**Trigger:** `workflow_dispatch` only, with input `scan_type` (`all`/`opa-only`/`tfsec-only`).

**Purpose:** A deeper security/compliance scan than `terraform-ci` — generates a fresh plan JSON from remote state, runs OPA against all three policies, runs tfsec with the full ruleset, writes a Step Summary, and notifies Slack.

**Job flow:**

```text
opa-full-scan ──┐
tfsec-deep    ──┴──► generate-reports → Step Summary + Slack
```

| Job | Description |
|---|---|
| `opa-full-scan` | Authenticates to AWS via OIDC, `terraform init` (S3 backend), `terraform plan -out=tfplan` (using the `TF_VAR_db_password` and `TF_VAR_gitops_repo_url` variables), exports JSON. Installs OPA, runs `deny` and `warn` for all three policies (`security`, `networking`, `compliance`). Merges the results into `opa-results.json` (artifact `opa-full-report`, retained 30 days). Fails the job if total `deny` > 0. |
| `tfsec-deep` | Installs tfsec via direct binary download, scans with the full ruleset (`json` + `lovely`), tallies total/CRITICAL/HIGH counts, artifact `tfsec-deep-report` (retained 30 days), does not block the job. |
| `generate-reports` | `needs: [opa-full-scan, tfsec-deep]`, `if: always()`. Writes the Step Summary (OPA table per policy, tfsec table per severity, job results table), notifies Slack. |

**Required secrets:** `AWS_DEV_ROLE_ARN`, `BUCKET_TF_STATE`, `TF_VAR_DB_PASSWORD`, `GITOPS_REPO_URL`, `SLACK_WEBHOOK_URL`

---

### app-ci.yaml

**Trigger:** `workflow_dispatch` only (no inputs).

**Purpose:** Application CI — triggered by changes to GitOps manifests or application source code.

**Job flow:**

```text
gitleaks ──► kustomize-validate ─┐
         ├──► opa-k8s-policies    ├──► app-ci-summary
         ├──► falco-validate      │
         └──► trivy-filesystem   ─┘
```

| Job | Description |
|---|---|
| `gitleaks` | Checks out full history (`fetch-depth: 0`), runs `gitleaks/gitleaks-action@v2`. Uploads SARIF (`results.sarif`) as artifact `gitleaks-report` only on failure. |
| `kustomize-validate` | `needs: gitleaks`. Installs `kustomize` + `kubeconform`. Builds 4 overlays (`platform-services`, `security`, `observability`, `applications/online-boutique` — skipped if the path doesn't exist) via `kustomize build --enable-helm`. Validates K8s schema with `kubeconform -strict -kubernetes-version 1.33.0`. Artifact `built-manifests`. |
| `opa-k8s-policies` | `needs: gitleaks`. Installs OPA, runs `opa test platform/security/opa/` (skipped if the directory doesn't exist) and `opa check` against each `.rego` file. Artifact `opa-k8s-test-results`. |
| `falco-validate` | `needs: gitleaks`. Installs Falco via APT, validates rules in `platform/security/falco/*.yaml|*.yml` with `falco --validate`; falls back to the `falcosecurity/falco:latest` Docker image if the native step fails. |
| `trivy-filesystem` | `needs: gitleaks`. `aquasecurity/trivy-action` pinned to the immutable commit SHA `ed142fdcb1de6fa9f3ba1550f1d92abfa9c81e51` (`v0.36.0`). Scans the filesystem, severity CRITICAL/HIGH, `exit-code: 0` (non-blocking). SARIF uploaded to the Security tab (category `Trivy-Filesystem-Scan`), artifact `trivy-fs-report`. |
| `app-ci-summary` | `needs` all 5 jobs above, `if: always()`. Writes the Step Summary, comments on the PR (with a separate warning if gitleaks failed), notifies Slack. |

**Required secrets:** `SLACK_WEBHOOK_URL`

---

### app-cd.yaml

**Trigger:** `workflow_dispatch` only, with inputs `service` (leave empty for auto-detect) and `environment` (`dev`).

**Concurrency:** `group: app-cd-<ref>`, `cancel-in-progress: false`.

**Purpose:** Build → Trivy image scan → push to ECR → update Kustomize → commit. **Partial update** design: each service in the matrix writes its own status file; `update-gitops` only bumps the image tag for services with `status=success` — one failing service does not block deployment of the others.

**Job flow:**

```text
detect-changes ──► build-and-scan (matrix per service, fail-fast:false) ──► update-gitops
```

| Job | Description |
|---|---|
| `detect-changes` | If a `service` input is given, uses it directly. Otherwise: a 3-dot `git diff` between `HEAD^1...HEAD` (falls back to `git diff HEAD`) under `microservices-application/`, extracting service names from the path. Outputs `services`, `has_changes`, `short_sha`. |
| `build-and-scan` | Matrix per service, `fail-fast: false`. OIDC auth + ECR login. Image name `<ECR_REGISTRY>/eks-devsecops-dev-<service>:<short_sha>` (plus a `latest` tag). No `Dockerfile` → skipped. Builds the image (labeled with `git.sha`/`git.ref`/`build.timestamp`). Scans the image with Trivy (same pinned SHA `ed142fdcb1de6fa9f3ba1550f1d92abfa9c81e51`/`v0.36.0`), JSON is the single source of truth → converted to SARIF. **Blocks the push if any CRITICAL CVE is found**. If it passes: pushes both tags to ECR, uploads SARIF to the Security tab (category `Trivy-Image-<service>`), uploads the Trivy report artifact. Always writes a final status (`success`/`blocked_critical_cve`/`skipped_no_dockerfile`/`failed`) as artifact `status-<service>`. |
| `update-gitops` | `needs: [detect-changes, build-and-scan]`, runs unless `build-and-scan` was `cancelled`. Downloads all `status-*` artifacts, filters services with `status=success`. Runs `kustomize edit set image` for each successful service against `KUSTOMIZE_OVERLAY_PATH`, commits as `github-actions[bot]` (using `GITOPS_BOT_TOKEN`), pushes to `main`. Notifies Slack (`warning` if any service was not updated, `good` if all succeeded). |

**Required secrets:** `AWS_DEV_ROLE_ARN`, `AWS_ACCOUNT_ID`, `GITOPS_BOT_TOKEN`, `SLACK_WEBHOOK_URL`

---

## OPA Policies

Both `terraform-cd.yaml` (job `opa-gate`) and `check-scan.yaml` (job `opa-full-scan`) call these 3 files under `platform/infrastructure/terraform/policies/`, evaluated via `opa eval` with input being the `terraform show -json` output of the current plan:

- **`deny`** — violations that fail the job/pipeline (blocking `apply`). The `deny` count across all three policies is summed; > 0 means failure.
- **`warn`** — logged to the run log/artifact only, never blocking.

`app-ci.yaml` (job `opa-k8s-policies`) uses OPA in a different way and is unrelated to these 3 files: it runs `opa test platform/security/opa/` (unit tests for Kubernetes admission policies) and `opa check` (syntax validation of `.rego` files).

> The specific rule content inside each `.rego` file below is not present in the 5 workflow files provided — only the package name and the fact that they're invoked via `deny`/`warn` can be confirmed.

---

### security.rego

**Package (confirmed from `opa eval` in terraform-cd.yaml / check-scan.yaml):** `data.terraform.security`

Evaluated via `data.terraform.security.deny` and `data.terraform.security.warn`. Specific rule content is not present in the provided workflow files.

---

### networking.rego

**Package (confirmed from `opa eval`):** `data.terraform.networking`

Evaluated via `data.terraform.networking.deny` and `data.terraform.networking.warn`. Specific rule content is not present in the provided workflow files.

---

### compliance.rego

**Package (confirmed from `opa eval`):** `data.terraform.compliance`

Evaluated via `data.terraform.compliance.deny` and `data.terraform.compliance.warn`. Specific rule content is not present in the provided workflow files.

---

## GitHub Secrets — Setup Guide

Navigate to: **Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required by | Notes |
|---|---|---|
| `AWS_DEV_ROLE_ARN` | `terraform-cd`, `check-scan`, `app-cd` | ARN of the IAM Role configured for GitHub OIDC federation |
| `BUCKET_TF_STATE` | `terraform-cd`, `check-scan` | Name of the S3 bucket used for Terraform remote state |
| `TF_VAR_DB_PASSWORD` | `check-scan` | Passed into the Terraform variable `TF_VAR_db_password` when generating the plan |
| `GITOPS_REPO_URL` | `terraform-cd` (`apply`, `destroy`), `check-scan` (`opa-full-scan`) | Passed into the Terraform variable `TF_VAR_gitops_repo_url` |
| `GITOPS_BOT_TOKEN` | `app-cd` | GitHub PAT with **Contents: read/write**, used to checkout and commit/push Kustomize updates to `main` |
| `AWS_ACCOUNT_ID` | `app-cd` | Used to build the ECR URI (`ECR_REGISTRY`) |
| `SLACK_WEBHOOK_URL` | All 5 workflows | Incoming Webhook URL for Slack |

---

## GitHub Environments — Setup Guide

Navigate to: **Repository → Settings → Environments → New environment**

Only `terraform-cd.yaml` declares an `environment:` at the job level:

| Environment | Used by | Note from the file |
|---|---|---|
| `dev-plan` | job `plan` | Assumed to already exist; create if missing |
| `dev-apply` | job `apply` | Must be created manually before first use, or the job will queue indefinitely |
| `dev-destroy` | job `destroy` | Must be created manually before first use; required reviewers are strongly recommended since this is a destructive action |

`terraform-ci.yaml`, `check-scan.yaml`, `app-ci.yaml`, and `app-cd.yaml` do not declare an `environment:` on any job.
