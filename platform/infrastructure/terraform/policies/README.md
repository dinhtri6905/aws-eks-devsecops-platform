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

The `opa-gate` job runs each policy's `deny` set first and sums the violation counts; if the total is greater than zero, the job exits 1 and the subsequent `apply` job never runs. `warn` sets are evaluated separately afterward purely for visibility in the GitHub Actions log — they do not affect the exit code.

> **Note:** `opa test` / `opa check` are **not** run against this directory. Those commands are used elsewhere in `app-ci.yaml` for a separate set of Kubernetes admission policies — the policies here are validated only by `opa eval` against a real plan, both in CI and locally.

---

## Policies

### security.rego

**Package:** `terraform.security`

Hardening checks for EKS, ECR, RDS, Security Groups, and IAM resources created by Terraform.

#### Deny Rules

| Resource type | Condition that triggers deny |
|---|---|
| `aws_eks_cluster` | `endpoint_public_access = true` and `public_access_cidrs` contains `0.0.0.0/0` |
| `aws_eks_cluster` | `enabled_cluster_log_types` is missing `audit` or `authenticator` |
| `aws_eks_node_group` | `disk_size` is less than 20 GiB |
| `aws_ecr_repository` | `image_scanning_configuration.scan_on_push` is not `true` |
| `aws_db_instance` | `storage_encrypted` is not `true` |
| `aws_db_instance` | `publicly_accessible = true` |
| `aws_db_instance` | `backup_retention_period` is less than 7 |
| `aws_security_group_rule` (ingress) | A sensitive port (`22`, `3389`, `3306`, `5432`, `6379`) is open to `0.0.0.0/0` |
| `aws_security_group_rule` (ingress) | `protocol = "-1"` (all traffic) open to `0.0.0.0/0` |
| `aws_security_group` | An inline ingress block opens a sensitive port to `0.0.0.0/0` |
| `aws_iam_policy` | A statement grants `Effect: Allow` with both `Action: "*"` and `Resource: "*"` |
| `aws_iam_user_policy` | Any policy attached directly to an IAM user (roles/IRSA required instead) |

#### Warn Rules

| Resource type | Condition that triggers warn |
|---|---|
| `aws_ecr_repository` | `image_tag_mutability = "MUTABLE"` — `IMMUTABLE` recommended for reproducible prod deployments |
| `aws_db_instance` | `deletion_protection = false` |
| `aws_db_instance` | `performance_insights_enabled = false` |
| `aws_eks_cluster` | `endpoint_public_access = true` (advisory — acceptable in dev, should be `false` in prod with VPN/bastion access) |

---

### networking.rego

**Package:** `terraform.networking`

Network security boundaries for the VPC, subnets, NAT gateways, Security Groups, and route tables.

#### Deny Rules

| Resource type | Condition that triggers deny |
|---|---|
| `aws_vpc` | `enable_dns_hostnames` is not `true` |
| `aws_vpc` | `enable_dns_support` is not `true` |
| `aws_subnet` | `map_public_ip_on_launch = true` on a subnet tagged as `private` |
| `aws_nat_gateway` | No NAT Gateway exists while private subnets are present in the plan |
| `aws_security_group` | An inline ingress rule allows all traffic (`protocol = "-1"`, port `0`–`0`) from `0.0.0.0/0` |
| `aws_security_group_rule` (ingress) | `protocol = "-1"` open to `0.0.0.0/0` |

#### Warn Rules

| Resource type | Condition that triggers warn |
|---|---|
| `aws_vpc` | CIDR block ends in `/8` — considered too broad |
| `aws_vpc` | No `aws_flow_log` resource references the VPC |
| `aws_subnet` | Missing both `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` tags (needed for AWS Load Balancer Controller subnet discovery) |
| `aws_nat_gateway` | Exactly one NAT Gateway exists but subnets span more than one Availability Zone (single point of failure — acceptable in dev, not in prod) |
| `aws_security_group` | A security group tagged `alb` opens a port other than `80`/`443` to `0.0.0.0/0` |
| `aws_route_table` | A route table tagged `public` has no route to an Internet Gateway (`igw-*`) |

---

### compliance.rego

**Package:** `terraform.compliance`

Tagging, encryption-at-rest, and backup/retention checks across the resources Terraform actually provisions (`aws_vpc`, `aws_subnet`, `aws_eks_cluster`, `aws_eks_node_group`, `aws_ecr_repository`, `aws_db_instance`, `aws_iam_role`, security groups, ALB). It does not check CloudTrail or S3, since this configuration does not provision those.

#### Deny Rules

| Resource type | Condition that triggers deny |
|---|---|
| `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_nat_gateway`, `aws_security_group`, `aws_eks_cluster`, `aws_eks_node_group`, `aws_ecr_repository`, `aws_lb`, `aws_db_instance`, `aws_iam_role` | No `tags` block at all |
| Same resource types as above | `tags` block exists but is missing a `Name` tag |
| `aws_db_instance` | `storage_encrypted` is not `true` *(also enforced in `security.rego` — defense in depth)* |
| `aws_ecr_repository` | `encryption_configuration.encryption_type` is not `AES256` or `KMS` |
| `aws_db_instance` | `backup_retention_period` is less than 7 *(also enforced in `security.rego`)* |

#### Warn Rules

| Resource type | Condition that triggers warn |
|---|---|
| `aws_db_instance` | `storage_type = "gp2"` — `gp3` recommended for cost/performance |
| `aws_eks_node_group` | No custom `launch_template` defined — advisory reminder to confirm EBS volume encryption is configured for prod |
| `aws_iam_role` | Role `name` does not contain a `-` — does not follow the `<project>-<env>-<purpose>-role` naming convention |
| `aws_db_instance` | `multi_az = false` — advisory; acceptable in dev, recommended `true` for prod HA |
| Any `aws_ecr_repository` present | No `aws_ecr_lifecycle_policy` resource found in the plan — recommended to bound image storage growth |

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

This is the same pattern the `opa-gate` job in `terraform-cd.yaml` runs in CI — running it locally before pushing lets you catch violations without waiting for the pipeline.
