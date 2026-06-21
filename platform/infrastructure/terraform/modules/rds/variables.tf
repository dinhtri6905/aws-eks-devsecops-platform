variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

# ============================================================
# NETWORKING & SG
# ============================================================
variable "private_subnet_ids" {
  description = "List of private subnet IDs for the RDS DB Subnet Group"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "Security Group ID to attach to the RDS instance"
  type        = string
}

# ============================================================
# DATABASE ENGINE
# ============================================================
variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

# ============================================================
# DATABASE CONFIGURATION
# ============================================================
variable "db_identifier" {
  description = "Unique identifier for the RDS instance"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database to create inside the RDS instance"
  type        = string
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
}

# ============================================================
# STORAGE
# ============================================================
variable "allocated_storage" {
  description = "Initial allocated storage in GiB"
  type        = number
}

variable "max_allocated_storage" {
  description = "Maximum storage autoscaling ceiling in GiB"
  type        = number
}

# ============================================================
# AVAILABILITY & BACKUP
# ============================================================
variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability (recommended for prod)"
  type        = bool
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (0 disables backups)"
  type        = number
}

variable "deletion_protection" {
  description = "Prevent the RDS instance from being deleted via Terraform or the console"
  type        = bool
  # default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the RDS instance (set false for prod)"
  type        = bool
  # default     = true
}
