# ============================================================
# RDS INSTANCE
# ============================================================
output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "db_instance_endpoint" {
  description = "Connection endpoint in host:port format"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "db_instance_address" {
  description = "Hostname of the RDS instance (without port)"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "db_instance_port" {
  description = "Port on which the RDS instance accepts connections"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the initial database created inside the RDS instance"
  value       = aws_db_instance.main.db_name
}

# ============================================================
# SUBNET GROUP
# ============================================================
output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

output "db_subnet_group_arn" {
  description = "ARN of the DB subnet group"
  value       = aws_db_subnet_group.main.arn
}
