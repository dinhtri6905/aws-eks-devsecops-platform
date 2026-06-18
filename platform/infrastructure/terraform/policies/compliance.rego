# platform/infrastructure/terraform/policies/compliance.rego
#
# Tagging and encryption compliance policies for the
# Cloud-Native Secure GitOps Platform on AWS EKS.
#
# Focuses on resources actually provisioned by
# platform/infrastructure/terraform (vpc, security-group, iam,
# eks, ecr, alb, rds) — does not check CloudTrail/S3 since this
# configuration does not provision those.
#
# deny  -> compliance violation, blocks deploy
# warn  -> recommendation, does not block deploy

package terraform.compliance

import rego.v1

# =============================================================================
# Tagging Policy
# Every major resource must carry a "Name" tag, consistent with
# the naming convention used across all Terraform modules
# (project_name-environment-resource).
# =============================================================================

taggable_resources := {
	"aws_vpc",
	"aws_subnet",
	"aws_internet_gateway",
	"aws_nat_gateway",
	"aws_security_group",
	"aws_eks_cluster",
	"aws_eks_node_group",
	"aws_ecr_repository",
	"aws_lb",
	"aws_db_instance",
	"aws_iam_role",
}

# Resources in the taggable set must define a "Name" tag.
deny contains msg if {
	resource := input.resource_changes[_]
	taggable_resources[resource.type]
	resource.change.after.tags
	not resource.change.after.tags.Name
	msg := sprintf(
		"Resource '%s' (%s): thieu tag 'Name' - bat buoc theo naming convention cua project",
		[resource.address, resource.type],
	)
}

# Resources in the taggable set must have a tags block at all
# (some resource types allow tags to be entirely omitted).
deny contains msg if {
	resource := input.resource_changes[_]
	taggable_resources[resource.type]
	not resource.change.after.tags
	msg := sprintf(
		"Resource '%s' (%s): khong co block 'tags' - phai co it nhat tag 'Name'",
		[resource.address, resource.type],
	)
}

# =============================================================================
# Encryption at Rest
# =============================================================================

# RDS storage must be encrypted (duplicated check from
# security.rego intentionally — compliance.rego is the
# authoritative source for encryption-at-rest requirements
# across all resource types, including future additions like
# EBS volumes / S3).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.storage_encrypted != true
	msg := sprintf(
		"[Compliance] RDS instance '%s': storage_encrypted phai la true (ma hoa du lieu luu tru)",
		[resource.address],
	)
}

# RDS must use gp3 (or another encryption-capable, modern
# storage type) — gp2 is allowed but discouraged.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.storage_type == "gp2"
	msg := sprintf(
		"[WARN][Compliance] RDS instance '%s': storage_type = gp2. Xem xet gp3 de toi uu chi phi/hieu nang.",
		[resource.address],
	)
}

# EKS managed node group EBS volumes should be encrypted via
# launch template; this configuration does not currently set a
# custom launch template, so emit an advisory reminder.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_eks_node_group"
	not resource.change.after.launch_template
	msg := sprintf(
		"[WARN][Compliance] EKS Node Group '%s': khong co launch_template tuy chinh - dam bao EBS volume encryption duoc cau hinh (vi du qua launch template rieng) cho prod.",
		[resource.address],
	)
}

# ECR repository images should be encrypted (AES256 or KMS).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_ecr_repository"
	enc := resource.change.after.encryption_configuration[_]
	not enc.encryption_type in {"AES256", "KMS"}
	msg := sprintf(
		"[Compliance] ECR Repository '%s': encryption_configuration.encryption_type phai la AES256 hoac KMS",
		[resource.address],
	)
}

# =============================================================================
# IAM Role naming / least privilege references
# (cross-checked with security.rego, kept here for the
# tagging/compliance reporting dimension)
# =============================================================================

# IAM roles created by the platform must follow the
# "<project>-<env>-..." naming convention so ownership is
# traceable in IAM/CloudTrail.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_role"
	name := resource.change.after.name
	not contains(name, "-")
	msg := sprintf(
		"[WARN][Compliance] IAM Role '%s': ten role '%s' khong theo naming convention '<project>-<env>-<purpose>-role'",
		[resource.address, name],
	)
}

# =============================================================================
# Backup / Retention
# =============================================================================

# RDS backup retention must be >= 7 days (duplicated with
# security.rego for the compliance reporting dimension —
# treated as a hard requirement for audit purposes).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.backup_retention_period < 7
	msg := sprintf(
		"[Compliance] RDS instance '%s': backup_retention_period = %d ngay, yeu cau >= 7 ngay theo chinh sach backup",
		[resource.address, resource.change.after.backup_retention_period],
	)
}

# =============================================================================
# WARN - Additional recommendations
# =============================================================================

# RDS should enable Multi-AZ for production-grade availability.
# Advisory only — dev typically uses multi_az = false to save
# cost.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.multi_az == false
	msg := sprintf(
		"[WARN][Compliance] RDS instance '%s': multi_az = false. Bat cho moi truong prod de dam bao High Availability.",
		[resource.address],
	)
}

# ECR lifecycle policies should exist to avoid unbounded image
# storage growth (cost control).
warn contains msg if {
	ecr_repos := [r | r := input.resource_changes[_]; r.type == "aws_ecr_repository"]
	count(ecr_repos) > 0
	lifecycle_policies := [r | r := input.resource_changes[_]; r.type == "aws_ecr_lifecycle_policy"]
	count(lifecycle_policies) == 0
	msg := "[WARN][Compliance] Khong tim thay aws_ecr_lifecycle_policy - nen thiet lap lifecycle policy de gioi han so luong image luu tru trong ECR"
}
