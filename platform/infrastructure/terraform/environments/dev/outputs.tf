# ============================================================
# VPC
# ============================================================
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of Private Subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IPs attached to NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}


# ============================================================
# VPC
# ============================================================