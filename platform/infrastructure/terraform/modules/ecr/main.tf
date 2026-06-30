locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ============================================================
# ECR REPOSITORIES
# ============================================================
resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_136:AWS managed AES256 encryption is sufficient for this educational DevSecOps project.

  for_each = toset(var.repository_names)

  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # Allows deleting repositories even if images are still inside (convenient for destroying files).
  force_delete = true

  tags = {
    Name       = "${local.name_prefix}/${each.value}"
    Repository = each.value
  }
}

# ============================================================
# LIFECYCLE POLICIES
# Rule 1 — Keep the last N tagged images with prefix "v"
# Rule 2 — Remove untagged images older than N days
# ============================================================
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = var.lifecycle_policy_enabled ? toset(var.repository_names) : toset([])
  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.tagged_image_keep_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.tagged_image_keep_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images older than ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ============================================================
# REPOSITORY POLICIES
# Statement 1 — Full management access for the owning account
# Statement 2 — Pull-only access for EKS worker nodes (least privilege)
# ============================================================
resource "aws_ecr_repository_policy" "this" {
  for_each   = toset(var.repository_names)
  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy"
        ]
      },
      {
        Sid    = "AllowEKSNodesPull"
        Effect = "Allow"
        Principal = {
          AWS = var.eks_node_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
