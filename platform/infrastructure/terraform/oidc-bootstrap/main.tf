terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Intentionally uses local state — this is a one-time bootstrap.
  # The S3 backend does not exist yet at this stage.
  # Do NOT delete terraform.tfstate after apply.
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# =============================================================================
# 1. GitHub OIDC Identity Provider
#    Allows GitHub Actions to authenticate to AWS without static credentials.
# =============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Stable thumbprint for the GitHub OIDC endpoint — does not rotate
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name        = "github-actions-oidc"
    ManagedBy   = "terraform"
    Environment = "shared"
  }
}

# =============================================================================
# 2. IAM Role — assumed by GitHub Actions via OIDC
#    Scoped to a specific GitHub org/repo to prevent unauthorized access.
# =============================================================================
resource "aws_iam_role" "github_actions_terraform_dev" {
  name        = "github-actions-terraform-dev"
  description = "Assumed by GitHub Actions via OIDC for Terraform CD (dev environment)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Allows all branches and workflow jobs within the specified repo
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "github-actions-terraform-dev"
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}

# =============================================================================
# 3. IAM Policy Attachment
#    AdministratorAccess is used here for the dev environment to allow
#    Terraform to provision any resource. For production, replace this
#    with a least-privilege custom policy scoped to required services only.
# =============================================================================
resource "aws_iam_role_policy_attachment" "admin_dev" {
  role       = aws_iam_role.github_actions_terraform_dev.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}