# =============================================================================
# policies/networking.rego
# OPA policy — Networking checks cho EKS platform (Terraform plan JSON)
#
# deny  → blocking
# warn  → non-blocking
#
# Resources được check:
#   aws_vpc, aws_subnet, aws_nat_gateway, aws_internet_gateway,
#   aws_route_table, aws_route, aws_security_group, aws_security_group_rule
# =============================================================================

package terraform.networking

import rego.v1

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
resources_of_type(resource_type) := [r |
  r := input.resource_changes[_]
  r.type == resource_type
  r.change.actions[_] in ["create", "update"]
]

# =============================================================================
# VPC
# =============================================================================

# [DENY] VPC phải bật DNS hostnames — EKS nodes cần resolve internal DNS
deny contains msg if {
  vpc := resources_of_type("aws_vpc")[_]
  not vpc.change.after.enable_dns_hostnames

  msg := sprintf(
    "[VPC][DENY] VPC '%v': enable_dns_hostnames phải là true (bắt buộc cho EKS).",
    [vpc.address]
  )
}

# [DENY] VPC phải bật DNS support
deny contains msg if {
  vpc := resources_of_type("aws_vpc")[_]
  not vpc.change.after.enable_dns_support

  msg := sprintf(
    "[VPC][DENY] VPC '%v': enable_dns_support phải là true (bắt buộc cho EKS).",
    [vpc.address]
  )
}

# [DENY] VPC CIDR không được dùng /8 hoặc /16 quá rộng mà không có lý do
warn contains msg if {
  vpc := resources_of_type("aws_vpc")[_]
  cidr := vpc.change.after.cidr_block

  # Detect /8 (quá rộng)
  endswith(cidr, "/8")

  msg := sprintf(
    "[VPC][WARN] VPC '%v': CIDR %v là /8 — rất rộng. Xem xét dùng /16 hoặc nhỏ hơn.",
    [vpc.address, cidr]
  )
}

# [WARN] VPC nên bật flow logs để audit traffic
warn contains msg if {
  vpc := resources_of_type("aws_vpc")[_]

  # Kiểm tra không có aws_flow_log nào reference VPC này
  flow_logs := [fl |
    fl := input.resource_changes[_]
    fl.type == "aws_flow_log"
    fl.change.after.vpc_id != null
  ]
  count(flow_logs) == 0

  msg := sprintf(
    "[VPC][WARN] VPC '%v': không có VPC Flow Logs. Nên bật để audit traffic và troubleshoot.",
    [vpc.address]
  )
}

# =============================================================================
# SUBNET
# =============================================================================

# [DENY] Private subnets dùng cho EKS nodes không được map public IP
deny contains msg if {
  subnet := resources_of_type("aws_subnet")[_]
  subnet.change.after.map_public_ip_on_launch == true

  # Chỉ fail nếu subnet có tag role là private hoặc eks
  tags := subnet.change.after.tags
  lower_tag_values := {lower(v) | v := tags[_]}

  # Nếu có tag chứa "private" hoặc "eks" mà lại map public IP → vi phạm
  lower_tag_values[v]
  contains(v, "private")

  msg := sprintf(
    "[SUBNET][DENY] Subnet '%v': map_public_ip_on_launch = true trên private subnet. EKS worker nodes không được có public IP.",
    [subnet.address]
  )
}

# [WARN] Subnet nên có tags rõ ràng để EKS và LBC nhận diện
warn contains msg if {
  subnet := resources_of_type("aws_subnet")[_]
  tags := subnet.change.after.tags

  # Không có tag "kubernetes.io/role/elb" hay "kubernetes.io/role/internal-elb"
  not has_elb_tag(tags)

  msg := sprintf(
    "[SUBNET][WARN] Subnet '%v': thiếu EKS subnet discovery tags (kubernetes.io/role/elb hoặc internal-elb). AWS LBC cần tag này.",
    [subnet.address]
  )
}

has_elb_tag(tags) if { tags["kubernetes.io/role/elb"] }
has_elb_tag(tags) if { tags["kubernetes.io/role/internal-elb"] }

# =============================================================================
# NAT GATEWAY
# =============================================================================

# [DENY] Phải có ít nhất 1 NAT Gateway — private subnets cần NAT để pull images
deny contains msg if {
  nat_gateways := resources_of_type("aws_nat_gateway")
  count(nat_gateways) == 0

  # Chỉ check nếu có private subnets trong plan
  private_subnets := [s |
    s := resources_of_type("aws_subnet")[_]
    tags := s.change.after.tags
    lower_tags := {lower(v) | v := tags[_]}
    lower_tags[v]
    contains(v, "private")
  ]
  count(private_subnets) > 0

  msg := "[NAT][DENY] Không có NAT Gateway nào được tạo nhưng có private subnets. EKS worker nodes cần NAT để kéo images."
}

# [WARN] Dev dùng 1 NAT là ổn, nhưng cần note về single point of failure
warn contains msg if {
  nat_gateways := resources_of_type("aws_nat_gateway")
  count(nat_gateways) == 1

  # Có nhiều hơn 1 AZ (check từ subnets)
  private_subnets := resources_of_type("aws_subnet")
  azs := {s.change.after.availability_zone | s := private_subnets[_]}
  count(azs) > 1

  msg := sprintf(
    "[NAT][WARN] Chỉ có 1 NAT Gateway nhưng có %v AZs. Dev OK, nhưng prod nên dùng NAT per AZ để tránh single point of failure.",
    [count(azs)]
  )
}

# =============================================================================
# SECURITY GROUP — kiểm tra cho EKS/RDS/ALB context
# =============================================================================

# [DENY] Security group không được cho phép tất cả traffic từ internet (0.0.0.0/0 trên port 0-65535 ingress)
deny contains msg if {
  sg := resources_of_type("aws_security_group")[_]
  ingress := sg.change.after.ingress[_]

  cidr := ingress.cidr_blocks[_]
  cidr == "0.0.0.0/0"
  ingress.from_port == 0
  ingress.to_port   == 0
  ingress.protocol  == "-1"

  msg := sprintf(
    "[SG][DENY] Security group '%v': ingress cho phép ALL traffic từ 0.0.0.0/0 (protocol=-1, port 0-0). Quá rộng.",
    [sg.address]
  )
}

# [DENY] Tương tự với aws_security_group_rule type ingress
deny contains msg if {
  rule := resources_of_type("aws_security_group_rule")[_]
  rule.change.after.type     == "ingress"
  rule.change.after.protocol == "-1"

  cidr := rule.change.after.cidr_blocks[_]
  cidr == "0.0.0.0/0"

  msg := sprintf(
    "[SG][DENY] Rule '%v': ingress ALL protocol từ 0.0.0.0/0. Phải specify port cụ thể.",
    [rule.address]
  )
}

# [WARN] ALB SG nên giới hạn — chỉ 80/443 từ internet
warn contains msg if {
  sg := resources_of_type("aws_security_group")[_]
  tags := sg.change.after.tags
  lower_name := lower(object.get(tags, "Name", ""))
  contains(lower_name, "alb")

  ingress := sg.change.after.ingress[_]
  cidr := ingress.cidr_blocks[_]
  cidr == "0.0.0.0/0"

  port := ingress.from_port
  not port in {80, 443}

  msg := sprintf(
    "[SG][WARN] ALB Security group '%v': mở port %v cho 0.0.0.0/0. ALB chỉ nên nhận 80/443 từ internet.",
    [sg.address, port]
  )
}

# =============================================================================
# ROUTE TABLE
# =============================================================================

# [WARN] Route table public phải có route ra Internet Gateway
warn contains msg if {
  rt := resources_of_type("aws_route_table")[_]
  tags := rt.change.after.tags
  lower_name := lower(object.get(tags, "Name", ""))
  contains(lower_name, "public")

  routes := rt.change.after.route
  igw_routes := [r | r := routes[_]; startswith(r.gateway_id, "igw-")]
  count(igw_routes) == 0

  msg := sprintf(
    "[ROUTE][WARN] Route table '%v' có vẻ là public nhưng không có route ra Internet Gateway.",
    [rt.address]
  )
}
