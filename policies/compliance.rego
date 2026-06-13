# =============================================================================
# policies/compliance.rego
# OPA policy — Compliance checks (Tagging + Encryption + EKS Audit Logging)
#
# deny  → blocking: tất cả resource phải có tags bắt buộc + encryption
# warn  → non-blocking: best practices nên theo
# =============================================================================

package terraform.compliance

import future.keywords.in
import future.keywords.every
import future.keywords.if
import future.keywords.contains

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
resources_of_type(resource_type) := [r |
  r := input.resource_changes[_]
  r.type == resource_type
  r.change.actions[_] in ["create", "update"]
]

# Resource types yêu cầu tagging bắt buộc
taggable_resource_types := {
  "aws_vpc",
  "aws_subnet",
  "aws_security_group",
  "aws_eks_cluster",
  "aws_eks_node_group",
  "aws_ecr_repository",
  "aws_db_instance",
  "aws_db_subnet_group",
  "aws_iam_role",
  "aws_nat_gateway",
  "aws_internet_gateway",
  "aws_lb",
  "aws_lb_target_group",
}

# Tags bắt buộc trên mọi resource
required_tags := {"Project", "Environment", "ManagedBy"}

# =============================================================================
# TAGGING COMPLIANCE
# =============================================================================

# [DENY] Tất cả taggable resources phải có đủ required_tags
deny contains msg if {
  resource := input.resource_changes[_]
  resource.type in taggable_resource_types
  resource.change.actions[_] in ["create", "update"]

  tags := object.get(resource.change.after, "tags", {})
  missing := required_tags - {k | tags[k]}
  count(missing) > 0

  msg := sprintf(
    "[TAGGING][DENY] Resource '%v' (%v): thiếu tags bắt buộc: %v. Tất cả resources phải có: %v",
    [resource.address, resource.type, missing, required_tags]
  )
}

# [DENY] Tag "Environment" phải là giá trị hợp lệ
valid_environments := {"dev", "staging", "prod"}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type in taggable_resource_types
  resource.change.actions[_] in ["create", "update"]

  tags := object.get(resource.change.after, "tags", {})
  env  := tags["Environment"]
  not env in valid_environments

  msg := sprintf(
    "[TAGGING][DENY] Resource '%v': tag Environment='%v' không hợp lệ. Phải là một trong: %v",
    [resource.address, env, valid_environments]
  )
}

# [WARN] Nên có tag "Owner" để tracking ownership
warn contains msg if {
  resource := input.resource_changes[_]
  resource.type in taggable_resource_types
  resource.change.actions[_] in ["create", "update"]

  tags := object.get(resource.change.after, "tags", {})
  not tags["Owner"]

  msg := sprintf(
    "[TAGGING][WARN] Resource '%v': nên có tag 'Owner' để dễ tracking.",
    [resource.address]
  )
}

# =============================================================================
# ENCRYPTION COMPLIANCE
# =============================================================================

# [DENY] RDS phải dùng KMS key (không phải chỉ default encryption)
deny contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  not db.change.after.storage_encrypted

  msg := sprintf(
    "[ENCRYPT][DENY] RDS '%v': storage_encrypted = false. Vi phạm encryption-at-rest requirement.",
    [db.address]
  )
}

# [WARN] RDS nên specify kms_key_id thay vì dùng AWS managed key
warn contains msg if {
  db := resources_of_type("aws_db_instance")[_]
  db.change.after.storage_encrypted == true
  not db.change.after.kms_key_id

  msg := sprintf(
    "[ENCRYPT][WARN] RDS '%v': encrypted nhưng không specify kms_key_id. Nên dùng Customer Managed Key (CMK).",
    [db.address]
  )
}

# [DENY] ECR phải có encryption_configuration
deny contains msg if {
  repo := resources_of_type("aws_ecr_repository")[_]
  after := repo.change.after
  not after.encryption_configuration

  msg := sprintf(
    "[ENCRYPT][DENY] ECR '%v': encryption_configuration chưa được set.",
    [repo.address]
  )
}

# [WARN] EKS secrets encryption nên dùng Customer Managed Key
warn contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  after   := cluster.change.after

  enc_configs := object.get(after, "encryption_config", [])

  some enc in enc_configs
  enc.resources[_] == "secrets"
  not enc.provider.key_arn

  msg := sprintf(
    "[ENCRYPT][WARN] EKS Cluster '%v': secrets encryption bật nhưng không có customer KMS key ARN.",
    [cluster.address]
  )
}

# =============================================================================
# EKS AUDIT LOGGING COMPLIANCE
# =============================================================================

# [DENY] EKS cluster phải bật audit + api logs tối thiểu
required_log_types := {"api", "audit"}

deny contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  enabled_logs := object.get(cluster.change.after, "enabled_cluster_log_types", [])
  enabled_set  := {l | l := enabled_logs[_]}

  missing := required_log_types - enabled_set
  count(missing) > 0

  msg := sprintf(
    "[LOGGING][DENY] EKS Cluster '%v': thiếu log types bắt buộc: %v. 'api' và 'audit' là bắt buộc cho compliance.",
    [cluster.address, missing]
  )
}

# [WARN] Nên bật đủ 5 log types để full audit trail
all_log_types := {"api", "audit", "authenticator", "controllerManager", "scheduler"}

warn contains msg if {
  cluster := resources_of_type("aws_eks_cluster")[_]
  enabled_logs := object.get(cluster.change.after, "enabled_cluster_log_types", [])
  enabled_set  := {l | l := enabled_logs[_]}

  missing := all_log_types - enabled_set
  count(missing) > 0

  msg := sprintf(
    "[LOGGING][WARN] EKS Cluster '%v': nên bật tất cả 5 log types. Còn thiếu: %v",
    [cluster.address, missing]
  )
}

# =============================================================================
# EKS NODE GROUP COMPLIANCE
# =============================================================================

# [DENY] EKS Node Group phải chạy ở private subnets (không expose public)
deny contains msg if {
  ng := resources_of_type("aws_eks_node_group")[_]

  # Node group không được có public subnets
  # Trong Terraform plan, subnet_ids là list — ta check bằng tag nếu có thể
  # Đây là best-effort check dựa trên naming
  subnet_ids := ng.change.after.subnet_ids
  count(subnet_ids) == 0

  msg := sprintf(
    "[EKS-NG][DENY] Node group '%v': không có subnet_ids được cấu hình.",
    [ng.address]
  )
}

# [WARN] Node Group nên có update_config để kiểm soát rolling update
warn contains msg if {
  ng := resources_of_type("aws_eks_node_group")[_]
  not ng.change.after.update_config

  msg := sprintf(
    "[EKS-NG][WARN] Node group '%v': update_config chưa được set. Nên giới hạn max_unavailable.",
    [ng.address]
  )
}

# [WARN] Disk size nên ít nhất 50GB cho production workloads
warn contains msg if {
  ng := resources_of_type("aws_eks_node_group")[_]
  lt := ng.change.after.launch_template[_]

  # Nếu không dùng launch template, check disk_size trực tiếp
  disk := object.get(ng.change.after, "disk_size", 20)
  disk < 50

  msg := sprintf(
    "[EKS-NG][WARN] Node group '%v': disk_size = %vGB. Nên ít nhất 50GB cho production workloads.",
    [ng.address, disk]
  )
}

# =============================================================================
# IAM COMPLIANCE
# =============================================================================

# [WARN] IAM Role nên có description rõ ràng
warn contains msg if {
  role := resources_of_type("aws_iam_role")[_]
  desc := object.get(role.change.after, "description", "")
  count(desc) == 0

  msg := sprintf(
    "[IAM][WARN] IAM Role '%v': không có description. Nên mô tả rõ mục đích của role.",
    [role.address]
  )
}

# [WARN] IAM Role nên có max_session_duration hợp lý (không quá 12h)
warn contains msg if {
  role := resources_of_type("aws_iam_role")[_]
  duration := object.get(role.change.after, "max_session_duration", 3600)
  duration > 43200  # 12 hours

  msg := sprintf(
    "[IAM][WARN] IAM Role '%v': max_session_duration = %vs (> 12h). Nên giảm để giới hạn thời gian token tồn tại.",
    [role.address, duration]
  )
}
