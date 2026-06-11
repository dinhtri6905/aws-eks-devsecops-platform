# ============================================================
# VPC
# ============================================================
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

# ============================================================
# PUBLIC SUBNETS
# ============================================================
output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = aws_subnet.public[*].id
}

# ============================================================
# PRIVATE SUBNETS
# ============================================================
output "private_subnet_ids" {
  description = "List of Private Subnet IDs"
  value       = aws_subnet.private[*].id
}

# ============================================================
# INTERNET GATEWAY
# ============================================================
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# ============================================================
# NAT GATEWAYS
# ============================================================
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IPs attached to NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}
# ============================================================
# ROUTE TABLES
# ============================================================
output "public_route_table_id" {
  description = "ID of the Public Route Table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of Private Route Table IDs"
  value       = aws_route_table.private[*].id
}