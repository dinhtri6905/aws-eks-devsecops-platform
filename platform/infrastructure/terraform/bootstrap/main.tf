# ============================================================
# KMS KEY FOR TERRAFORM STATE ENCRYPTION
# ============================================================
resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform remote state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name    = "eks-devsecops-tfstate-kms"
    Purpose = "terraform-state-encryption"
  }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/eks-devsecops-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

# ============================================================
# S3 BUCKET: TERRAFORM STATE
# ============================================================
resource "aws_s3_bucket" "tfstate" {
  bucket = var.tfstate_bucket_name

  force_destroy = true # nếu sang prod thì phải đổi sang false

  lifecycle {
    prevent_destroy = false # nếu sang prod thì phải đổi sang true
  }

  tags = {
    Name    = var.tfstate_bucket_name
    Purpose = "terraform-state"
  }
}

# ============================================================
# VERSIONING
# ============================================================
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================
# ENCRYPTION
# ============================================================
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.tfstate.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# ============================================================
# PUBLIC ACCESS BLOCK
# ============================================================
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# OWNERSHIP CONTROLS
# ============================================================
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ============================================================
# LIFECYCLE RULE
# ============================================================
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ============================================================
# DYNAMODB TABLE FOR STATE LOCKING
# ============================================================
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.dynamodb_lock_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = false # nếu sang prod thì phải đổi sang true
  }

  tags = {
    Name    = var.dynamodb_lock_table_name
    Purpose = "terraform-state-lock"
  }
}
