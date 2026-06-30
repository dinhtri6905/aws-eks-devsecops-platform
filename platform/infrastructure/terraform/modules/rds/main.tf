locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ============================================================
# DB SUBNET GROUP
# RDS must be placed in at least 2 AZs even for Single-AZ deployments
# ============================================================
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Subnet group for RDS instance"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# ============================================================
# DB PARAMETER GROUP
# Custom parameters for PostgreSQL 15 — enables query logging for dev observability
# ============================================================
resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-postgres16-params"
  family      = "postgres16"
  description = "Custom parameter group for PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  tags = {
    Name = "${local.name_prefix}-postgres16-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# RDS INSTANCE — PostgreSQL
# ============================================================
resource "aws_db_instance" "main" {
  #checkov:skip=CKV_AWS_354:Performance Insights is disabled for this cost-optimized development environment.
  #checkov:skip=CKV_AWS_118:Enhanced Monitoring is disabled to reduce operational cost in this educational environment.
  #checkov:skip=CKV_AWS_157:Single-AZ deployment is sufficient for this educational DevSecOps project.
  #checkov:skip=CKV_AWS_293:Deletion protection is intentionally disabled to support automated Terraform destroy in development.
  #checkov:skip=CKV_AWS_161:IAM database authentication is not required for this educational project and the application uses standard database credentials.

  identifier = var.db_identifier

  # Engine
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  # The master password is generated and stored by AWS RDS in Secrets Manager
  # (no plaintext password variable, nothing to leak via tfvars/CI logs/state).
  # Retrieve it via `aws_db_instance.main.master_user_secret[0].secret_arn`
  # or `aws secretsmanager get-secret-value`.
  manage_master_user_password = true

  port     = 5432

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  # Availability
  multi_az = var.multi_az

  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name

  # Ensure RDS logs are enabled.
  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  # Backup
  backup_retention_period  = var.backup_retention_period
  backup_window            = "03:00-04:00"
  maintenance_window       = "Mon:04:00-Mon:05:00"
  delete_automated_backups = true

  # Performance Insights — free tier (7 days retention)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot

  ### PROD CONFIG: skip_final_snapshot = false AND final_snapshot_identifier is REQUIRED  ###
  # final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.db_identifier}-final-snapshot"

  # Apply changes immediately in non-prod
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = {
    Name = var.db_identifier
  }
}
