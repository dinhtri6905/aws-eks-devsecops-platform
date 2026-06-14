# =============================================================================
# policies/security.rego
# OPA policy — Security checks cho EKS platform (Terraform plan JSON)
#
# deny  → blocking: CI fails, terraform apply bị chặn
# warn  → non-blocking: hiện warning, không fail job
#
# Resources được check:
#   aws_eks_cluster, aws_ecr_repository, aws_db_instance,
#   aws_security_group, aws_security_group_rule, aws_iam_role_policy,
#   aws_iam_policy, aws_iam_role_policy_attachment
# =============================================================================

package terraform.security

import future.keywords.in
import future.keywords.every
import future.keywords.if
import future.keywords.contains

# ---------------------------------------------------------------------------
# Helper: lấy tất cả resource changes theo type
# ---------------------------------------------------------------------------
resources_of_type(resource_type) := [r |
  r := input.resource_changes[_]
  r.type == resource_type
  r.change.actions[_] in ["create", "update"]
]

# =============================================================================
# EKS CLUSTER SECURITY
# =============================================================================

# [DENY] EKS endpoint public access không được bật mà không có CIDR restriction
deny contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  cluster.change.after.kubernetes_network_config != null

  vpc_config := cluster.change.after.vpc_config[_]
  vpc_config.endpoint_public_access == true

  # public_access_cidrs phải được giới hạn — không được là 0.0.0.0/0 duy nhất
  cidrs := vpc_config.public_access_cidrs
  count(cidrs) == 1
  cidrs[0] == "0.0.0.0/0"

  msg := sprintf(
    "[EKS][DENY] Cluster '%v': public endpoint mở cho 0.0.0.0/0. Giới hạn public_access_cidrs hoặc bật private-only.",
    [cluster.address]
  )
}

# [DENY] EKS cluster phải bật private access
deny contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  vpc_config := cluster.change.after.vpc_config[_]
  not vpc_config.endpoint_private_access

  msg := sprintf(
    "[EKS][DENY] Cluster '%v': endpoint_private_access phải là true.",
    [cluster.address]
  )
}

# [DENY] EKS cluster phải bật encryption cho secrets
deny contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  after := cluster.change.after

  # Không có encryption_config nào cho secrets
  not any_secret_encryption(after)

  msg := sprintf(
    "[EKS][DENY] Cluster '%v': encryption_config cho secrets chưa được bật. Dùng KMS key.",
    [cluster.address]
  )
}

any_secret_encryption(cluster_config) if {
  enc := cluster_config.encryption_config[_]
  enc.resources[_] == "secrets"
}

# [WARN] EKS cluster nên bật tất cả log types
warn contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  enabled_logs := cluster.change.after.enabled_cluster_log_types

  required_logs := {"api", "audit", "authenticator", "controllerManager", "scheduler"}
  missing := required_logs - {l | l := enabled_logs[_]}
  count(missing) > 0

  msg := sprintf(
    "[EKS][WARN] Cluster '%v': thiếu log types: %v. Nên bật đầy đủ để audit.",
    [cluster.address, missing]
  )
}

# =============================================================================
# ECR SECURITY
# =============================================================================

# [DENY] ECR repository phải bật scan_on_push
deny contains msg if {
  repo := resources_of_type("aws_ecr_repository")[_]
  image_scanning := repo.change.after.image_scanning_configuration[_]
  not image_scanning.scan_on_push

  msg := sprintf(
    "[ECR][DENY] Repository '%v': scan_on_push phải là true để phát hiện CVE khi push image.",
    [repo.address]
  )
}

# [DENY] ECR repository phải bật encryption (AES256 hoặc KMS)
deny contains msg if {
  repo := resources_of_type("aws_ecr_repository")[_]
  after := repo.change.after

  # Không có encryption_configuration
  not after.encryption_configuration

  msg := sprintf(
    "[ECR][DENY] Repository '%v': encryption_configuration chưa được cấu hình.",
    [repo.address]
  )
}

# [WARN] ECR nên dùng KMS thay AES256 cho encryption tốt hơn
warn contains msg if {
  repo := resources_of_type("aws_ecr_repository")[_]
  enc := repo.change.after.encryption_configuration[_]
  enc.encryption_type == "AES256"

  msg := sprintf(
    "[ECR][WARN] Repository '%v': dùng KMS encryption thay AES256 để quản lý key tốt hơn.",
    [repo.address]
  )
}

# [WARN] ECR image_tag_mutability nên là IMMUTABLE trong prod
warn contains msg if {
  repo := resources_of_type("aws_ecr_repository")[_]
  repo.change.after.image_tag_mutability == "MUTABLE"

  msg := sprintf(
    "[ECR][WARN] Repository '%v': image_tag_mutability là MUTABLE. Nên IMMUTABLE cho prod để tránh overwrite.",
    [repo.address]
  )
}

# =============================================================================
# RDS SECURITY
# =============================================================================

# [DENY] RDS không được là publicly_accessible
deny contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  db.change.after.publicly_accessible == true

  msg := sprintf(
    "[RDS][DENY] Instance '%v': publicly_accessible = true. RDS phải ở private subnet.",
    [db.address]
  )
}

# [DENY] RDS phải bật storage_encrypted
deny contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  not db.change.after.storage_encrypted

  msg := sprintf(
    "[RDS][DENY] Instance '%v': storage_encrypted phải là true.",
    [db.address]
  )
}

# [DENY] RDS phải có backup_retention_period > 0
deny contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  db.change.after.backup_retention_period == 0

  msg := sprintf(
    "[RDS][DENY] Instance '%v': backup_retention_period = 0. Phải giữ backup ít nhất 7 ngày.",
    [db.address]
  )
}

# [WARN] RDS nên bật deletion_protection trong prod
warn contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  not db.change.after.deletion_protection

  msg := sprintf(
    "[RDS][WARN] Instance '%v': deletion_protection chưa bật. Nên bật cho prod để tránh xóa nhầm.",
    [db.address]
  )
}

# [WARN] RDS nên bật auto_minor_version_upgrade
warn contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  not db.change.after.auto_minor_version_upgrade

  msg := sprintf(
    "[RDS][WARN] Instance '%v': auto_minor_version_upgrade chưa bật.",
    [db.address]
  )
}

# =============================================================================
# SECURITY GROUP — không mở port nguy hiểm ra internet
# =============================================================================

dangerous_ports := {22, 3389, 5432, 3306, 6379, 27017}
open_cidrs      := {"0.0.0.0/0", "::/0"}

# [DENY] Security group rule không được mở port nguy hiểm ra 0.0.0.0/0
deny contains msg if {
  rule := resources_of_type("aws_security_group_rule")[_]
  rule.change.after.type == "ingress"

  cidr := rule.change.after.cidr_blocks[_]
  cidr in open_cidrs

  from_port := rule.change.after.from_port
  to_port   := rule.change.after.to_port

  port := dangerous_ports[_]
  from_port <= port
  to_port   >= port

  msg := sprintf(
    "[SG][DENY] Rule '%v': port %v mở cho %v. Không được expose port nhạy cảm ra internet.",
    [rule.address, port, cidr]
  )
}

# [DENY] Security group inline không được mở port nguy hiểm ra internet
deny contains msg if {
  sg := resources_of_type("aws_security_group")[_]
  ingress := sg.change.after.ingress[_]

  cidr := ingress.cidr_blocks[_]
  cidr in open_cidrs

  port := dangerous_ports[_]
  ingress.from_port <= port
  ingress.to_port   >= port

  msg := sprintf(
    "[SG][DENY] Security group '%v': ingress mở port %v cho %v.",
    [sg.address, port, cidr]
  )
}

# [WARN] Egress không nên mở toàn bộ ra internet nếu có thể hạn chế
warn contains msg if {
  sg := resources_of_type("aws_security_group")[_]
  egress := sg.change.after.egress[_]

  cidr := egress.cidr_blocks[_]
  cidr == "0.0.0.0/0"
  egress.from_port == 0
  egress.to_port == 0

  msg := sprintf(
    "[SG][WARN] Security group '%v': egress mở toàn bộ 0.0.0.0/0. Xem xét restrict nếu có thể.",
    [sg.address]
  )
}

# =============================================================================
# IAM — tránh wildcard quá rộng
# =============================================================================

# [DENY] IAM policy không được dùng Action=* cùng Resource=*
deny contains msg if {
  policy := resources_of_type("aws_iam_role_policy")[_]
  doc    := json.unmarshal(policy.change.after.policy)
  stmt   := doc.Statement[_]

  stmt.Effect == "Allow"
  actions   := stmt.Action if is_array(stmt.Action) else [stmt.Action]
  resources := stmt.Resource if is_array(stmt.Resource) else [stmt.Resource]

  actions[_]   == "*"
  resources[_] == "*"

  msg := sprintf(
    "[IAM][DENY] Role policy '%v': Action=* + Resource=* là wildcard nguy hiểm. Dùng least-privilege.",
    [policy.address]
  )
}

# [DENY] aws_iam_policy cũng không được dùng Action=* + Resource=*
deny contains msg if {
  policy := resources_of_type("aws_iam_policy")[_]
  doc    := json.unmarshal(policy.change.after.policy)
  stmt   := doc.Statement[_]

  stmt.Effect == "Allow"
  actions   := stmt.Action if is_array(stmt.Action) else [stmt.Action]
  resources := stmt.Resource if is_array(stmt.Resource) else [stmt.Resource]

  actions[_]   == "*"
  resources[_] == "*"

  msg := sprintf(
    "[IAM][DENY] Policy '%v': Action=* + Resource=* vi phạm least-privilege.",
    [policy.address]
  )
}

is_array(x) if { type_name(x) == "array" }
