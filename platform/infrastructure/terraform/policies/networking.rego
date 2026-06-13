# platform/infrastructure/terraform/policies/networking.rego
#
# Networking policies for the Cloud-Native Secure GitOps
# Platform on AWS EKS. Ensures correct VPC configuration,
# subnet placement (public for ALB/NAT, private for EKS nodes
# and RDS), and NAT Gateway availability.
#
# deny  -> structural network violation, blocks deploy
# warn  -> design recommendation, does not block deploy

package terraform.networking

# =============================================================================
# VPC - Basic configuration
# =============================================================================

# VPC must enable DNS hostnames (required for EKS and RDS
# endpoint resolution).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_vpc"
	resource.change.after.enable_dns_hostnames == false
	msg := sprintf(
		"VPC '%s': enable_dns_hostnames phai la true (bat buoc cho EKS va RDS endpoint)",
		[resource.address],
	)
}

# VPC must enable DNS support (resolution).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_vpc"
	resource.change.after.enable_dns_support == false
	msg := sprintf(
		"VPC '%s': enable_dns_support phai la true",
		[resource.address],
	)
}

# =============================================================================
# Subnets - Public vs Private separation
# =============================================================================

# Subnets tagged Tier=Private must not auto-assign public IPs.
# EKS worker nodes and RDS live in private subnets.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_subnet"
	resource.change.after.map_public_ip_on_launch == true
	resource.change.after.tags.Tier == "Private"
	msg := sprintf(
		"Subnet '%s' (Tier=Private): map_public_ip_on_launch phai la false - EKS nodes/RDS phai o private subnet",
		[resource.address],
	)
}

# Subnets tagged Tier=Public should auto-assign public IPs
# (needed for the ALB and NAT Gateway placement).
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_subnet"
	resource.change.after.map_public_ip_on_launch == false
	resource.change.after.tags.Tier == "Public"
	msg := sprintf(
		"[WARN] Subnet '%s' (Tier=Public): map_public_ip_on_launch = false. ALB/NAT Gateway thuong can public IP.",
		[resource.address],
	)
}

# =============================================================================
# NAT Gateway - Required for private subnet egress
# =============================================================================

# At least one NAT Gateway must exist so that EKS nodes in
# private subnets can pull images from ECR / reach AWS APIs.
deny contains msg if {
	nat_gateways := [r | r := input.resource_changes[_]; r.type == "aws_nat_gateway"]
	count(nat_gateways) == 0
	msg := "Khong tim thay aws_nat_gateway - EKS worker nodes va RDS trong private subnet se khong co duong ra internet (vi du: pull image tu ECR, goi AWS API)"
}

# =============================================================================
# EKS Cluster - Subnet placement
# =============================================================================

# EKS cluster vpc_config.subnet_ids must include subnets from
# at least 2 distinct values (proxy for multi-AZ — exact AZ
# checking requires cross-referencing subnet resources, so this
# checks subnet count as a baseline).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_eks_cluster"
	vpc_config := resource.change.after.vpc_config[_]
	count(vpc_config.subnet_ids) < 2
	msg := sprintf(
		"EKS Cluster '%s': vpc_config.subnet_ids phai co >= 2 subnet (multi-AZ) de dam bao High Availability",
		[resource.address],
	)
}

# =============================================================================
# ALB - Multi-AZ & internet-facing
# =============================================================================

# ALB must span at least 2 subnets for high availability.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_lb"
	resource.change.after.load_balancer_type == "application"
	count(resource.change.after.subnets) < 2
	msg := sprintf(
		"ALB '%s': phai deploy tren >= 2 subnet (multi-AZ) de dam bao High Availability",
		[resource.address],
	)
}

# The platform's entrypoint ALB is expected to be
# internet-facing (internal == false) so it can receive traffic
# from the internet via the Internet Gateway.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_lb"
	resource.change.after.load_balancer_type == "application"
	resource.change.after.internal == true
	msg := sprintf(
		"[WARN] ALB '%s': internal = true. Neu day la entrypoint ALB cho Online Boutique, can internal = false de nhan traffic tu internet.",
		[resource.address],
	)
}

# =============================================================================
# RDS - Subnet group required
# =============================================================================

# RDS must be placed in a DB subnet group (private subnets),
# not deployed without one.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	not resource.change.after.db_subnet_group_name
	msg := sprintf(
		"RDS instance '%s': phai co db_subnet_group_name - RDS phai nam trong private subnet group",
		[resource.address],
	)
}

# =============================================================================
# Security Group - Descriptions and DB egress
# =============================================================================

# Security groups must have a meaningful description (not the
# Terraform/AWS default placeholder).
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	desc := resource.change.after.description
	lower(desc) == "managed by terraform"
	msg := sprintf(
		"Security Group '%s': description '%s' qua chung, hay mo ta ro chuc nang (vi du: 'RDS - allow PostgreSQL from EKS nodes')",
		[resource.address, desc],
	)
}

# RDS security group rules should not allow unrestricted
# egress to 0.0.0.0/0.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	contains(lower(resource.change.after.name), "rds")
	egress := resource.change.after.egress[_]
	egress.protocol == "-1"
	egress.cidr_blocks[_] == "0.0.0.0/0"
	msg := sprintf(
		"[WARN] Security Group '%s' (RDS): khong nen co unrestricted egress (protocol=-1, 0.0.0.0/0)",
		[resource.address],
	)
}

# =============================================================================
# WARN - Design recommendations
# =============================================================================

# VPC Flow Logs help with audit and troubleshooting.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_vpc"
	flow_logs := [r | r := input.resource_changes[_]; r.type == "aws_flow_log"]
	count(flow_logs) == 0
	msg := sprintf(
		"[WARN] VPC '%s': khong tim thay aws_flow_log resource - nen bat VPC Flow Logs de ho tro audit/debug",
		[resource.address],
	)
}

# ALB listeners should prefer HTTPS (443) for encrypted traffic.
# Advisory only — dev environments commonly use plain HTTP on
# port 80 behind the platform ALB.
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_lb_listener"
	resource.change.after.protocol == "HTTP"
	msg := sprintf(
		"[WARN] ALB Listener '%s': protocol = HTTP. Xem xet them listener HTTPS (443) voi ACM certificate cho prod.",
		[resource.address],
	)
}
