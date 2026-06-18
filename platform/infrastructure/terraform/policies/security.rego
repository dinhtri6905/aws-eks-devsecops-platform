# platform/infrastructure/terraform/policies/security.rego
#
# Security policies for the Cloud-Native Secure GitOps Platform
# on AWS EKS. Evaluated against `terraform show -json tfplan`.
#
# Resources checked: EKS, ECR, RDS, Security Groups, IAM.
#
# deny  -> serious violation, blocks deploy
# warn  -> advisory, does not block deploy

package terraform.security

import rego.v1

# =============================================================================
# EKS - Cluster endpoint access
# =============================================================================

# EKS cluster should not expose the API server publicly without
# any restriction. If public access is enabled, it must be
# restricted to specific CIDR blocks (not 0.0.0.0/0).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_eks_cluster"
	vpc_config := resource.change.after.vpc_config[_]
	vpc_config.endpoint_public_access == true
	cidr := vpc_config.public_access_cidrs[_]
	cidr == "0.0.0.0/0"
	msg := sprintf(
		"EKS Cluster '%s': public_access_cidrs khong duoc chua '0.0.0.0/0' khi endpoint_public_access = true. Gioi han theo IP/CIDR cu the.",
		[resource.address],
	)
}

# EKS cluster control plane logging should be enabled for at
# least the audit and authenticator log types.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_eks_cluster"
	enabled_logs := resource.change.after.enabled_cluster_log_types
	required := {"audit", "authenticator"}
	provided := {log | log := enabled_logs[_]}
	missing := required - provided
	count(missing) > 0
	msg := sprintf(
		"EKS Cluster '%s': enabled_cluster_log_types thieu cac log type bat buoc: %v",
		[resource.address, missing],
	)
}

# =============================================================================
# EKS Node Group - Capacity & disk
# =============================================================================

# Node group disk size should not be smaller than 20 GiB
# (insufficient space for container images and logs).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_eks_node_group"
	resource.change.after.disk_size < 20
	msg := sprintf(
		"EKS Node Group '%s': disk_size = %d GiB, yeu cau >= 20 GiB",
		[resource.address, resource.change.after.disk_size],
	)
}

# =============================================================================
# ECR - Image scanning & encryption
# =============================================================================

# ECR repositories must have scan_on_push enabled.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_ecr_repository"
	scan_config := resource.change.after.image_scanning_configuration[_]
	scan_config.scan_on_push != true
	msg := sprintf(
		"ECR Repository '%s': image_scanning_configuration.scan_on_push phai la true",
		[resource.address],
	)
}

# ECR repositories must not use mutable tags in production-like
# repos (best practice: IMMUTABLE for reproducible deployments).
# This is a warning, not a hard block, since dev often uses
# MUTABLE for convenience during early iteration.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_ecr_repository"
	resource.change.after.image_tag_mutability == "MUTABLE"
	msg := sprintf(
		"[WARN] ECR Repository '%s': image_tag_mutability = MUTABLE. Xem xet IMMUTABLE cho prod de dam bao reproducibility.",
		[resource.address],
	)
}

# =============================================================================
# RDS - Encryption, public access, backups
# =============================================================================

# RDS storage must be encrypted at rest.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.storage_encrypted != true
	msg := sprintf(
		"RDS instance '%s': storage_encrypted phai la true",
		[resource.address],
	)
}

# RDS must not be publicly accessible — only EKS worker nodes
# in private subnets should reach it via Security Group rules.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.publicly_accessible == true
	msg := sprintf(
		"RDS instance '%s': publicly_accessible phai la false - chi EKS worker nodes (private subnet) duoc truy cap",
		[resource.address],
	)
}

# RDS backup retention period must be at least 7 days.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.backup_retention_period < 7
	msg := sprintf(
		"RDS instance '%s': backup_retention_period = %d, yeu cau >= 7 ngay",
		[resource.address, resource.change.after.backup_retention_period],
	)
}

# =============================================================================
# Security Group - Sensitive ports must not be open to the internet
# =============================================================================

sensitive_ports := {22, 3389, 3306, 5432, 6379}

# No ingress rule may open SSH, RDP, MySQL, PostgreSQL, or Redis
# ports to 0.0.0.0/0.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group_rule"
	resource.change.after.type == "ingress"
	resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
	port := sensitive_ports[_]
	resource.change.after.from_port <= port
	resource.change.after.to_port >= port
	msg := sprintf(
		"Security Group Rule '%s': port %d khong duoc mo ra internet (0.0.0.0/0)",
		[resource.address, port],
	)
}

# Security group rules must not allow all traffic (-1) ingress
# from 0.0.0.0/0.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group_rule"
	resource.change.after.type == "ingress"
	resource.change.after.protocol == "-1"
	resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
	msg := sprintf(
		"Security Group Rule '%s': khong duoc cho phep tat ca traffic (protocol=-1) tu 0.0.0.0/0",
		[resource.address],
	)
}

# Inline ingress blocks on aws_security_group resources are also
# checked (some modules define ingress inline rather than via
# aws_security_group_rule).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	ingress := resource.change.after.ingress[_]
	ingress.cidr_blocks[_] == "0.0.0.0/0"
	port := sensitive_ports[_]
	ingress.from_port <= port
	ingress.to_port >= port
	msg := sprintf(
		"Security Group '%s': inline ingress mo port %d ra 0.0.0.0/0",
		[resource.address, port],
	)
}

# =============================================================================
# IAM - Least privilege
# =============================================================================

# IAM policy must not grant Action=* on Resource=* (full admin).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_policy"
	policy := json.unmarshal(resource.change.after.policy)
	statement := policy.Statement[_]
	statement.Effect == "Allow"
	action_is_wildcard(statement.Action)
	resource_is_wildcard(statement.Resource)
	msg := sprintf(
		"IAM Policy '%s': khong duoc cap quyen Action=* tren Resource=* (full admin permissions)",
		[resource.address],
	)
}

action_is_wildcard(action) if action == "*"

action_is_wildcard(action) if {
	is_array(action)
	action[_] == "*"
}

resource_is_wildcard(res) if res == "*"

resource_is_wildcard(res) if {
	is_array(res)
	res[_] == "*"
}

# IAM policies must not be attached directly to IAM users —
# use roles (e.g. IRSA) or groups instead.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_user_policy"
	msg := sprintf(
		"IAM User Policy '%s': khong gan policy truc tiep vao user, hay dung IAM Role (vi du: IRSA cho service account)",
		[resource.address],
	)
}

# =============================================================================
# WARN - advisory checks
# =============================================================================

# RDS should enable deletion_protection to avoid accidental
# deletion (especially for prod).
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.deletion_protection == false
	msg := sprintf(
		"[WARN] RDS instance '%s': nen bat deletion_protection = true de tranh xoa nham",
		[resource.address],
	)
}

# RDS should enable Performance Insights for observability.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	resource.change.after.performance_insights_enabled == false
	msg := sprintf(
		"[WARN] RDS instance '%s': nen bat performance_insights_enabled de ho tro observability",
		[resource.address],
	)
}

# EKS cluster should disable public endpoint access entirely in
# prod-like environments (advisory only — dev commonly keeps it
# enabled for convenience).
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_eks_cluster"
	vpc_config := resource.change.after.vpc_config[_]
	vpc_config.endpoint_public_access == true
	msg := sprintf(
		"[WARN] EKS Cluster '%s': endpoint_public_access = true. Xem xet false cho prod va truy cap qua VPN/bastion.",
		[resource.address],
	)
}
