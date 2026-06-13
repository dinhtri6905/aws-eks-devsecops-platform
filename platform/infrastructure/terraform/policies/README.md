# OPA Policies — Terraform Plan Enforcement

Policy-as-Code layer for the **Cloud-Native Secure GitOps Platform on AWS EKS**.

All three policy files live under `platform/infrastructure/terraform/policies/` and are evaluated by the `opa-gate` job in `terraform-cd.yaml` against a `terraform show -json` plan output **before** any `terraform apply` is permitted to run.

---

## How It Works

```text
terraform plan -out tfplan
       │
       ▼
terraform show -json tfplan  →  tf-plan.json
       │
       ▼
opa eval --data security.rego    --input tf-plan.json  "data.terraform.security.deny"
opa eval --data networking.rego  --input tf-plan.json  "data.terraform.networking.deny"
opa eval --data compliance.rego  --input tf-plan.json  "data.terraform.compliance.deny"
       │
       ├── total deny count == 0  →  apply proceeds
       └── total deny count  > 0  →  apply BLOCKED, violations printed to log
```

Each policy exposes two rule sets:

| Set | Effect | When triggered |
|---|---|---|
| `deny` | **Blocks** `terraform apply` | Security or compliance violation that must be fixed before deployment |
| `warn` | Logged only, non-blocking | Findings that should be reviewed but do not require immediate remediation |

---

## Policies

### security.rego

**Package:** `data.terraform.security`

Enforces security hardening for EKS, ECR, RDS, and IAM resources created by Terraform.

#### Deny Rules

| ID | Resource type | Condition that triggers deny |
|---|---|---|
| `eks_public_endpoint_unrestricted` | `aws_eks_cluster` | `endpoint_public_access = true` and `public_access_cidrs` is not restricted (contains `0.0.0.0/0`) |
| `eks_secrets_not_encrypted` | `aws_eks_cluster` | `encryption_config` block is missing or does not include `secrets` as a resource type |
| `ecr_scan_on_push_disabled` | `aws_ecr_repository` | `image_scanning_configuration.scan_on_push = false` |
| `rds_publicly_accessible` | `aws_db_instance` | `publicly_accessible = true` |
| `rds_storage_not_encrypted` | `aws_db_instance` | `storage_encrypted = false` |
| `iam_wildcard_action_and_resource` | `aws_iam_policy` / `aws_iam_role_policy` | Policy document contains `Action: "*"` with `Resource: "*"` and `Effect: "Allow"` |

#### Warn Rules

| ID | Resource type | Condition that triggers warn |
|---|---|---|
| `ecr_tag_mutability_mutable` | `aws_ecr_repository` | `image_tag_mutability = "MUTABLE"` — immutable tags recommended to prevent tag overwriting |
| `rds_deletion_protection_disabled` | `aws_db_instance` | `deletion_protection = false` — protects against accidental instance deletion |
| `iam_wildcard_resource` | `aws_iam_policy` | Policy uses `Resource: "*"` without a wildcard action — should be scoped where possible |

---

### networking.rego

**Package:** `data.terraform.networking`

Enforces network security boundaries for the EKS cluster VPC, subnets, and Security Groups.

#### Deny Rules

| ID | Resource type | Condition that triggers deny |
|---|---|---|
| `sg_allow_all_inbound` | `aws_security_group` / `aws_vpc_security_group_ingress_rule` | Ingress rule with `from_port = 0`, `to_port = 0`, `protocol = "-1"` open to `0.0.0.0/0` or `::/0` |
| `sg_ssh_open_to_internet` | `aws_security_group` | Port `22` open to `0.0.0.0/0` or `::/0` in any ingress rule |
| `eks_nodes_in_public_subnet` | `aws_eks_node_group` | `subnet_ids` references subnets tagged or named as public — EKS worker nodes must run in private subnets only |

#### Warn Rules

| ID | Resource type | Condition that triggers warn |
|---|---|---|
| `vpc_flow_logs_disabled` | `aws_vpc` | No `aws_flow_log` resource references this VPC — flow logs should be enabled for audit and incident response |
| `public_subnet_auto_assign_ip` | `aws_subnet` | `map_public_ip_on_launch = true` — flag for review to confirm intent; acceptable for NAT Gateway subnets |

---

### compliance.rego

**Package:** `data.terraform.compliance`

Enforces organizational tagging standards and encryption-at-rest requirements across all resource types.

#### Required Tags

All taggable AWS resources (`aws_vpc`, `aws_subnet`, `aws_eks_cluster`, `aws_db_instance`, `aws_ecr_repository`, `aws_s3_bucket`, `aws_security_group`, `aws_iam_role`, etc.) must carry the following tags:

| Tag key | Expected value | Severity if missing |
|---|---|---|
| `Project` | Any non-empty string | **deny** |
| `Environment` | Any non-empty string (e.g. `dev`, `prod`) | **deny** |
| `ManagedBy` | `terraform` | **deny** |
| `Owner` | Any non-empty string (team or individual) | warn |

#### Encryption Rules

| ID | Resource type | Condition that triggers deny |
|---|---|---|
| `ebs_volume_not_encrypted` | `aws_ebs_volume` | `encrypted = false` or attribute absent |
| `eks_node_root_volume_not_encrypted` | `aws_eks_node_group` | `launch_template` does not specify an encrypted root volume |
| `s3_no_server_side_encryption` | `aws_s3_bucket` | No `aws_s3_bucket_server_side_encryption_configuration` resource associated with the bucket |
| `rds_storage_not_encrypted` | `aws_db_instance` | `storage_encrypted = false` *(also enforced in `security.rego` — defence in depth)* |

#### Warn Rules

| ID | Resource type | Condition that triggers warn |
|---|---|---|
| `s3_versioning_disabled` | `aws_s3_bucket` | No `aws_s3_bucket_versioning` resource with `status = "Enabled"` — required for state bucket recovery |
| `kms_key_rotation_disabled` | `aws_kms_key` | `enable_key_rotation = false` — automatic rotation recommended for all KMS keys |

---

## Running Policies Locally

Install OPA:

```bash
# macOS
brew install opa

# Linux
curl -sSL -o /usr/local/bin/opa \
  https://openpolicyagent.org/downloads/latest/opa_linux_amd64_static
chmod +x /usr/local/bin/opa
```

Generate a plan JSON from the dev environment:

```bash
cd platform/infrastructure/terraform/environments/dev

terraform init \
  -backend-config="bucket=<your-state-bucket>" \
  -backend-config="region=ap-southeast-1"

terraform plan -out=tfplan
terraform show -json tfplan > /tmp/tf-plan.json
```

Evaluate all policies:

```bash
POLICIES_DIR="platform/infrastructure/terraform/policies"
PLAN="/tmp/tf-plan.json"

for policy in security networking compliance; do
  echo "=== ${policy}.rego ==="

  echo "--- DENY ---"
  opa eval \
    --format pretty \
    --data "${POLICIES_DIR}/${policy}.rego" \
    --input "$PLAN" \
    "data.terraform.${policy}.deny"

  echo "--- WARN ---"
  opa eval \
    --format pretty \
    --data "${POLICIES_DIR}/${policy}.rego" \
    --input "$PLAN" \
    "data.terraform.${policy}.warn"

  echo ""
done
```

Run OPA unit tests (if test files are present alongside the policy files):

```bash
opa test platform/infrastructure/terraform/policies/ --verbose
```

---

## Adding a New Rule

1. Open the relevant `.rego` file (`security.rego`, `networking.rego`, or `compliance.rego`).
2. Add the rule to the `deny` or `warn` set with a descriptive message string.
3. Write a corresponding unit test in `<policy>_test.rego` covering both the passing and failing case.
4. Run `opa test` locally to confirm the test passes.
5. Run `opa eval` against a real plan JSON to confirm the rule fires as expected.
6. Open a PR — `app-ci.yaml` will automatically run `opa test` and `opa check` against all `.rego` files.

> Keep rule messages human-readable — they are printed directly in the GitHub Actions log and Slack notifications when a violation blocks apply.
