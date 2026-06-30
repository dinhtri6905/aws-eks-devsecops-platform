# CI/CD Pipelines & OPA Policies

Reference documentation for the GitHub Actions automation and OPA policy enforcement layer of the **Cloud-Native Secure GitOps Platform on AWS EKS**.

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
    ├── check-scan.yaml     # Scheduled deep security scan: OPA full + tfsec extended ruleset
    ├── app-ci.yaml         # Application CI: gitleaks / kustomize validate / OPA k8s / falco / trivy fs
    └── app-cd.yaml         # Application CD: build → Trivy image scan → push ECR → update Kustomize → commit

platform/infrastructure/terraform/
└── policies/
    ├── security.rego       # EKS / ECR / RDS / IAM hardening rules
    ├── networking.rego     # VPC / Subnet / Security Group rules
    └── compliance.rego     # Tagging standards and encryption-at-rest requirements
```

---

## End-to-End Flow

```text
 Developer pushes to feature/** or develop
          │
          ▼
 ┌──────────────────────────────────────────┐
 │  app-ci.yaml                             │
 │                                          │
 │  gitleaks (hard gate)                    │
 │      ├── kustomize-validate              │
 │      ├── opa-k8s-policies               │
 │      ├── falco-validate                 │
 │      └── trivy-filesystem               │
 │                                          │
 │  └── PR comment + Slack notification    │
 └──────────────────────────────────────────┘
          │
          │  PR approved and merged to main
          │
          ├─────────────────────────────────────────────────────────────┐
          │                                                             │
          ▼  (terraform/** changed)                                     ▼  (microservices-application/** changed)
 ┌────────────────────────────┐                              ┌──────────────────────────────────┐
 │  terraform-cd.yaml         │                              │  app-cd.yaml                     │
 │                            │                              │                                  │
 │  plan                      │                              │  detect-changes                  │
 │   └── opa-gate             │                              │   └── build-and-scan (matrix)    │
 │         └── apply          │                              │         └── update-gitops        │
 └────────────────────────────┘                              │               │                  │
                                                             │               ▼                  │
                                                             │  kustomization.yaml committed    │
                                                             └──────────────────────────────────┘
                                                                             │
                                                                             ▼
                                                              ArgoCD detects manifest change
                                                                             │
                                                                             ▼
                                                              Rolling update deployed to EKS

 Nightly (scheduled):
 └── check-scan.yaml
       ├── opa-full-scan  →  all three policies against latest plan JSON
       └── tfsec-deep     →  extended ruleset scan
             └── SARIF upload → GitHub Security tab + Slack
```

---

## GitHub Actions Workflows

### terraform-ci.yaml

**Trigger:** Push or PR to `develop` / `feature/**` — paths `platform/infrastructure/terraform/**`

**Purpose:** Static analysis gate that runs before any infrastructure change reaches a plan or apply. Catches formatting inconsistencies, provider misconfigurations, and security findings early in the development loop.

**Job flow:**

```text
fmt-validate ─┐
tflint        ├──► ci-summary → PR comment + Slack
tfsec         │
checkov       ┘
```

All four analysis jobs run in parallel. `ci-summary` collects results regardless of individual job outcomes and produces a unified PR comment and Slack notification.

| Job | Tool | Scope |
|---|---|---|
| `fmt-validate` | `terraform fmt -check` + `terraform validate` | Formatting consistency and HCL syntax |
| `tflint` | TFLint + AWS ruleset | AWS provider best practices, deprecated arguments, invalid resource configurations |
| `tfsec` | tfsec | Static security misconfigurations across all `.tf` files |
| `checkov` | Checkov | CIS Benchmark, NIST, and SOC 2 compliance mappings for AWS resources |
| `ci-summary` | — | Aggregates all results, posts PR comment, notifies Slack |

**Security tab integration:** `tfsec` and `checkov` produce SARIF output uploaded to the GitHub Security tab under **Security → Code scanning alerts**.

**Required secrets:** `SLACK_WEBHOOK_URL`

---

### terraform-cd.yaml

**Trigger:**
- Automatic — push to `main` when files under `platform/infrastructure/terraform/**` change
- Manual — `workflow_dispatch` with `action` (`plan` / `apply` / `destroy`) and `environment` (`dev`)

**Purpose:** Controlled, policy-gated infrastructure delivery. An OPA evaluation step sits between `plan` and `apply` — no infrastructure change is applied without passing all three policy files.

**Job flow:**

```text
plan ──► opa-gate ──► apply
              │
              └──► BLOCKED if any deny violation

destroy  (manual dispatch only — isolated environment with required reviewers)
```

| Job | Description |
|---|---|
| `plan` | Runs `terraform init` and `terraform plan -out tfplan`. Exports the plan as JSON via `terraform show -json` and uploads it as a workflow artifact for OPA consumption. |
| `opa-gate` | Downloads the plan artifact and evaluates it against `security.rego`, `networking.rego`, and `compliance.rego`. Any `deny` violation causes this job to exit non-zero, preventing `apply` from running. `warn` violations are printed to the log but do not block. |
| `apply` | Runs only when: OPA gate passes **and** either a push to `main` with plan changes (`exitcode=2`), or a manual `apply` dispatch. Uses the saved plan — no re-plan at apply time. |
| `destroy` | Manual dispatch only. Runs in the `dev-destroy` GitHub Environment. Add required reviewers to this environment to prevent accidental teardown. |

**OPA gate summary:**

| Policy | `deny` result | `warn` result |
|---|---|---|
| `security.rego` | Blocks apply | Logged only |
| `networking.rego` | Blocks apply | Logged only |
| `compliance.rego` | Blocks apply | Logged only |

**Concurrency:** `cancel-in-progress: false` — concurrent runs for the same environment are queued, not cancelled, to prevent Terraform state corruption.

**Required secrets:** `AWS_DEV_ROLE_ARN`, `BUCKET_TF_STATE`, `TF_VAR_DB_PASSWORD`, `GITOPS_REPO_URL`, `SLACK_WEBHOOK_URL`

---

### check-scan.yaml

**Trigger:** Scheduled cron (nightly). Also dispatchable manually via `workflow_dispatch`.

**Purpose:** Continuous, change-independent security scanning. Catches newly published CVEs, policy coverage drift, and misconfigurations that emerge between commits — scenarios that PR-triggered CI cannot detect.

**Job flow:**

```text
opa-full-scan ─┐
tfsec-deep     ├──► scan-summary → SARIF upload + Slack
               ┘
```

| Job | Description |
|---|---|
| `opa-full-scan` | Evaluates all three OPA policies against the latest plan JSON. Reports all `deny` and `warn` violations with full detail. |
| `tfsec-deep` | Runs tfsec with the extended ruleset, including rules intentionally suppressed in `terraform-ci.yaml` to reduce developer feedback noise. |
| `scan-summary` | Uploads SARIF to the GitHub Security tab. Sends a Slack notification with violation counts. |

**Required secrets:** `AWS_DEV_ROLE_ARN`, `BUCKET_TF_STATE`, `SLACK_WEBHOOK_URL`

---

### app-ci.yaml

**Trigger:** Push to `develop` / `feature/**` or PR to `develop` — paths `platform/gitops/**`, `platform/security/**`, `microservices-application/**`

**Purpose:** Validates GitOps manifests, Kubernetes admission policies, Falco rules, and application source code before any image build or cluster deployment occurs.

**Job flow:**

```text
gitleaks (hard gate)
    ├──► kustomize-validate
    ├──► opa-k8s-policies
    ├──► falco-validate
    └──► trivy-filesystem
              │
              └──► app-ci-summary → PR comment + Slack
```

| Job | Tool | Scope |
|---|---|---|
| `gitleaks` | Gitleaks | Secret scanning across full git history. **Hard gate** — all downstream jobs declare `needs: gitleaks`. A single detected secret stops the entire pipeline. |
| `kustomize-validate` | Kustomize + kubeconform | Builds all dev overlays with `kustomize build` and validates the rendered output against Kubernetes `1.33.0` schema using `--strict --ignore-missing-schemas`. |
| `opa-k8s-policies` | OPA | Runs unit tests for Kubernetes admission policies in `platform/security/opa/`. Also validates `.rego` syntax with `opa check`. |
| `falco-validate` | Falco | Validates Falco rule files in `platform/security/falco/`. Uses native Falco binary with an automatic Docker fallback if native installation fails in the runner environment. |
| `trivy-filesystem` | Trivy | Filesystem CVE scan of source code before any image build. Non-blocking (`exit-code: 0`) — findings are reported to the Security tab but do not fail the workflow. |
| `app-ci-summary` | — | Posts a results table as a PR comment. Notifies Slack. |

**Required secrets:** `SLACK_WEBHOOK_URL`

---

### app-cd.yaml

**Trigger:**
- Automatic — push to `main` when files under `microservices-application/**` change
- Manual — `workflow_dispatch` with optional `service` name override and `environment` choice

**Purpose:** Builds and scans service images, pushes to ECR, and commits updated Kustomize image tags to the GitOps repository. ArgoCD detects the manifest change and performs a rolling update on the cluster — no manual `kubectl` or Helm commands required.

**Job flow:**

```text
detect-changes
    └──► build-and-scan  (matrix — one parallel job per changed service)
              │
              ├── docker build
              ├── trivy SARIF scan     → GitHub Security tab
              ├── trivy table scan     → workflow log
              ├── trivy JSON scan      → count CRITICAL CVEs
              │     └── BLOCK push if CRITICAL count > 0
              └── docker push (SHA tag + latest) → ECR
                        │
                        └──► update-gitops
                                  │
                                  ├── kustomize edit set image (per service)
                                  ├── git commit + push to main
                                  └── Slack notification
                                            │
                                            ▼
                                  ArgoCD detects change → rolling update
```

**Trivy gate logic:**

Trivy runs three times per service, in sequence:

1. **SARIF scan** — always uploaded to the GitHub Security tab regardless of outcome.
2. **Table scan** — printed to the workflow log in human-readable format.
3. **JSON scan** — parsed to count `CRITICAL` CVEs with `ignore-unfixed: true`. If count > 0, the CVE list is printed and the job exits with code `1`, **blocking the ECR push**. `HIGH` findings are reported but do not block.

**Image tagging strategy:**

| Tag | Format | Purpose |
|---|---|---|
| SHA tag | `<7-char git short SHA>` | Immutable reference committed into `kustomization.yaml` — the tag ArgoCD deploys |
| `latest` | Updated on every push | Convenience reference only — not used by ArgoCD or any automated process |

**Concurrency:** `cancel-in-progress: false` — queued, never cancelled. Prevents race conditions on ECR pushes and concurrent GitOps commits.

**Required secrets:** `AWS_DEV_ROLE_ARN`, `AWS_ACCOUNT_ID`, `GITOPS_BOT_TOKEN`, `SLACK_WEBHOOK_URL`

---

## OPA Policies

All three policy files live under `platform/infrastructure/terraform/policies/` and are evaluated by the `opa-gate` job in `terraform-cd.yaml` against a `terraform show -json` plan output before any apply is permitted.

Each policy exposes two rule sets:

- **`deny`** — violations that block `terraform apply`. The `opa-gate` job sums deny counts across all three policies and fails if the total is greater than zero.
- **`warn`** — findings printed to the workflow log and Slack. Non-blocking. Intended for issues that should be reviewed but do not require immediate remediation.

---

### security.rego

**Package:** `data.terraform.security`

Enforces security hardening for EKS, ECR, RDS, and IAM resources.

| Rule | Severity | Description |
|---|---|---|
| EKS public endpoint unrestricted | `deny` | `endpoint_public_access = true` is only permitted when `public_access_cidrs` does not contain `0.0.0.0/0` |
| EKS secrets encryption missing | `deny` | Cluster must define an `encryption_config` block covering the `secrets` resource type with a KMS key |
| ECR scan on push disabled | `deny` | All ECR repositories must have `image_scanning_configuration.scan_on_push = true` |
| ECR tag mutability mutable | `warn` | Repositories should use `image_tag_mutability = "IMMUTABLE"` to prevent tag overwriting |
| RDS publicly accessible | `deny` | `publicly_accessible = true` is not permitted on any RDS instance |
| RDS storage not encrypted | `deny` | `storage_encrypted = true` is required on all RDS instances |
| RDS deletion protection off | `warn` | `deletion_protection = true` is recommended to guard against accidental instance deletion |
| IAM wildcard action and resource | `deny` | Policies must not grant `Action: "*"` with `Resource: "*"` and `Effect: "Allow"` |
| IAM wildcard resource | `warn` | `Resource: "*"` should be scoped to specific ARNs where possible |

---

### networking.rego

**Package:** `data.terraform.networking`

Enforces network security boundaries for VPC, subnets, and Security Groups.

| Rule | Severity | Description |
|---|---|---|
| Security Group allows all inbound | `deny` | No ingress rule may use protocol `-1` (all traffic) open to `0.0.0.0/0` or `::/0` |
| SSH open to internet | `deny` | Port `22` must not be reachable from `0.0.0.0/0` or `::/0` on any Security Group |
| EKS nodes in public subnet | `deny` | EKS managed node groups must reference private subnets only |
| VPC flow logs disabled | `warn` | Every VPC should have an associated `aws_flow_log` resource for audit and incident response |
| Public subnet auto-assign IP | `warn` | `map_public_ip_on_launch = true` is flagged for review to confirm the assignment is intentional |

---

### compliance.rego

**Package:** `data.terraform.compliance`

Enforces organizational tagging standards and encryption-at-rest requirements across all resource types.

**Required tags** — all taggable resources (`aws_vpc`, `aws_subnet`, `aws_eks_cluster`, `aws_db_instance`, `aws_ecr_repository`, `aws_s3_bucket`, `aws_security_group`, `aws_iam_role`, etc.) must carry:

| Tag key | Expected value | Severity if absent |
|---|---|---|
| `Project` | Any non-empty string | `deny` |
| `Environment` | Any non-empty string (e.g. `dev`, `prod`) | `deny` |
| `ManagedBy` | `terraform` | `deny` |
| `Owner` | Any non-empty string | `warn` |

**Encryption rules:**

| Rule | Severity | Description |
|---|---|---|
| EBS volume not encrypted | `deny` | All `aws_ebs_volume` resources and EKS node group root volumes must have `encrypted = true` |
| S3 bucket no server-side encryption | `deny` | Every S3 bucket must have an associated `aws_s3_bucket_server_side_encryption_configuration` |
| RDS storage not encrypted | `deny` | `storage_encrypted = true` required — defence-in-depth alongside `security.rego` |
| S3 versioning disabled | `warn` | S3 buckets should have versioning enabled — required for state bucket point-in-time recovery |
| KMS key rotation disabled | `warn` | `enable_key_rotation = true` is recommended for all customer-managed KMS keys |

---

## GitHub Secrets — Setup Guide

Navigate to: **Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required by | Description and how to obtain |
|---|---|---|
| `AWS_DEV_ROLE_ARN` | `terraform-cd`, `app-cd`, `check-scan` | ARN of the IAM Role configured for GitHub OIDC federation. See [IAM OIDC Role](#iam-oidc-role) below. |
| `BUCKET_TF_STATE` | `terraform-cd`, `check-scan` | Name of the S3 bucket used for Terraform remote state. Bucket name only — not the full ARN. Created during bootstrap. |
| `TF_VAR_DB_PASSWORD` | `terraform-cd` | RDS master password. Minimum 8 characters. Must not contain `@`, `/`, or `"`. Never hardcode — always supply via this secret. |
| `GITOPS_REPO_URL` | `terraform-cd` | Full HTTPS URL of this repository: `https://github.com/<org>/<repo>.git`. Passed to the ArgoCD bootstrap Terraform module as `gitops_repo_url`. |
| `GITOPS_BOT_TOKEN` | `app-cd` | GitHub Personal Access Token (PAT) with **Contents: read/write** permission on this repository. Used by `update-gitops` to commit Kustomize image tag changes to `main`. Create at **Settings → Developer settings → Fine-grained personal access tokens**. |
| `AWS_ACCOUNT_ID` | `app-cd` | 12-digit AWS account ID. Used to construct ECR repository URIs. Retrieve with: `aws sts get-caller-identity --query Account --output text` |
| `SLACK_WEBHOOK_URL` | all workflows | Incoming Webhook URL for your Slack channel. Create at **api.slack.com/apps → Incoming Webhooks → Add New Webhook to Workspace**. |

### IAM OIDC Role

The role referenced by `AWS_DEV_ROLE_ARN` must trust GitHub's OIDC provider. Minimum trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::041659741748:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:dinhtri6905/aws-eks-devsecops-platform:*"
        }
      }
    }
  ]
}
```

For production, tighten `sub` to a specific environment to restrict assumption to the apply job only:

```json
"token.actions.githubusercontent.com:sub": "repo:<your-org>/<your-repo>:environment:dev-apply"
```

### Minimum IAM permissions

For dev, attaching `AdministratorAccess` to the OIDC role is the fastest path to get started. For production, scope the role to the following:

| Service | Minimum permissions |
|---|---|
| EKS | `eks:*` |
| EC2 / VPC | `ec2:*` |
| IAM | Create/update/delete roles, policies, instance profiles, OIDC providers |
| ECR | `ecr:GetAuthorizationToken`, `ecr:*` on target repositories |
| S3 | `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on the state bucket |
| DynamoDB | `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on the lock table |
| KMS | `kms:Decrypt`, `kms:GenerateDataKey` on the state encryption key |
| RDS | `rds:*` |

---

## GitHub Environments — Setup Guide

Navigate to: **Repository → Settings → Environments → New environment**

Environments add deployment protection rules — required reviewer approvals and branch restrictions — between pipeline jobs.

| Environment | Used by | Recommended protection |
|---|---|---|
| `dev-plan` | `terraform-cd` → `plan` | None — runs automatically on every push |
| `dev-apply` | `terraform-cd` → `apply` | Optional for dev. Add 1+ required reviewers when promoting to production. |
| `dev-destroy` | `terraform-cd` → `destroy` | **Required reviewers (2+) mandatory.** Deployment branch restricted to `main` only. |

To configure protection rules: open the environment → **Required reviewers** → add users or teams → **Deployment branches** → **Selected branches** → add `main`.

> `dev-apply` may be left unprotected in a development environment where auto-apply on merge to `main` is the intended workflow. `dev-destroy` must always be protected — an unprotected destroy environment with `workflow_dispatch` access can result in complete infrastructure loss.
