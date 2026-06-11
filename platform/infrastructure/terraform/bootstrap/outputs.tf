# ============================================================
# S3 BUCKET
# ============================================================
# output "tfstate_bucket_id" {
#   description = "Terraform State Bucket ID"
#   value       = aws_s3_bucket.tfstate.id
# }

# output "tfstate_bucket_arn" {
#   description = "Terraform State Bucket ARN"
#   value       = aws_s3_bucket.tfstate.arn
# }

output "tfstate_bucket_name" {
  description = "Terraform State Bucket Name"
  value       = aws_s3_bucket.tfstate.bucket
}

# ============================================================
# DYNAMODB LOCK TABLE
# ============================================================
output "dynamodb_lock_table_name" {
  description = "Terraform Lock Table Name"
  value       = aws_dynamodb_table.terraform_lock.name
}

# output "dynamodb_lock_table_arn" {
#   description = "Terraform Lock Table ARN"
#   value       = aws_dynamodb_table.terraform_lock.arn
# }

# ============================================================
# KMS
# ============================================================
# output "kms_key_id" {
#   description = "KMS Key ID"
#   value       = aws_kms_key.tfstate.id
# }

output "kms_key_arn" {
  description = "KMS Key ARN"
  value       = aws_kms_key.tfstate.arn
}

# ============================================================
# Output backend config nếu thích
# ============================================================
# output "backend_configuration" {
#   description = "Terraform backend configuration"

#   value = {
#     bucket         = aws_s3_bucket.tfstate.bucket
#     dynamodb_table = aws_dynamodb_table.terraform_lock.name
#     region         = var.aws_region
#     kms_key_arn    = aws_kms_key.tfstate.arn
#   }
# }