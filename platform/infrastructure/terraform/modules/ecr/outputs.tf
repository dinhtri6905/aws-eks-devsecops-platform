# ============================================================
# REPOSITORY URLS
# Used in: CI/CD pipelines (docker push), Kubernetes manifests (image field)
# ============================================================
output "repository_urls" {
  description = "Map of repository name to full ECR URL (e.g. 123456789.dkr.ecr.ap-southeast-1.amazonaws.com/project/service)"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

# ============================================================
# REPOSITORY ARNS
# Used in: IAM policies granting push/pull access
# ============================================================
output "repository_arns" {
  description = "Map of repository name to ARN"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

# ============================================================
# REGISTRY ID
# The AWS account ID that hosts the registry
# ============================================================
output "registry_id" {
  description = "AWS account ID of the ECR registry"
  value       = length(var.repository_names) > 0 ? aws_ecr_repository.this[var.repository_names[0]].registry_id : ""
}
