# OIDC Bootstrap — GitHub Actions ↔ AWS

This one-time bootstrap provisions the AWS resources required for GitHub Actions to authenticate to AWS using **OpenID Connect (OIDC)** — no static IAM access keys needed.

## What this creates

| Resource | Description |
|----------|-------------|
| `aws_iam_openid_connect_provider` | Trusts GitHub's OIDC token issuer |
| `aws_iam_role` | IAM Role assumed by GitHub Actions workflows |
| `aws_iam_role_policy_attachment` | Attaches `AdministratorAccess` to the role (dev only) |

## Directory structure

```
oidc-bootstrap/
├── main.tf               # OIDC provider + IAM role + policy attachment
├── variables.tf          # Input variable declarations
├── outputs.tf            # Outputs: role ARN, OIDC provider ARN, account ID
├── terraform.tfvars      # Your actual values (not committed to Git)
├── terraform.tfvars.example  # Template — copy this to get started
└── README.md
```

> **Note:** This module uses **local state** intentionally. The S3 remote backend does not exist yet at bootstrap time. Keep `terraform.tfstate` safe and never commit it to Git.

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.10.0`
- AWS CLI configured with credentials that have permission to create IAM resources
- A GitHub repository where the workflows will run

---

## Getting started

### 1. Copy and edit the variables file

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in your values:

```hcl
aws_region  = "ap-southeast-1"   # AWS region
github_org  = "your-org-name"    # GitHub org or personal username
github_repo = "your-repo-name"   # Repository name (without org prefix)
```

### 2. Verify your AWS credentials

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-user"
}
```

### 3. Navigate to this directory

```bash
cd infrastructure/terraform/oidc-bootstrap
```

### 4. Initialise Terraform

```bash
terraform init
```

### 5. Review the plan

```bash
terraform plan
```

### 6. Apply

```bash
terraform apply
```

Type `yes` when prompted.

### 7. Copy the role ARN from the output

```bash
terraform output role_arn
# → arn:aws:iam::123456789012:role/github-actions-terraform-dev
```

---

## After apply — add the GitHub Secret

Go to your GitHub repository:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value |
|-------------|-------|
| `AWS_DEV_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-actions-terraform-dev` |

Once added, the Terraform CD workflow (`terraform-cd.yaml`) will be able to assume this role via OIDC on every run.

---

## Security notes

- The IAM Role's trust policy is scoped to **your specific GitHub repository** (`repo:ORG/REPO:*`). No other repository can assume this role.
- `AdministratorAccess` is intentional for the dev environment to give Terraform full provisioning rights. For production, replace it with a least-privilege custom policy.
- `terraform.tfvars` and `terraform.tfstate` are excluded from Git via `.gitignore` — never commit these files.

---

## .gitignore

Make sure your `.gitignore` includes:

```gitignore
# Terraform state — contains sensitive output values
*.tfstate
*.tfstate.backup
.terraform/

# Local variable overrides
terraform.tfvars
```
