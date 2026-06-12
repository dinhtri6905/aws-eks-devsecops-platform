# ============================================================
# LBC IRSA ROLE
# Pass lbc_role_arn to the LBC Helm chart values:
#   serviceAccount.annotations."eks.amazonaws.com/role-arn" = lbc_role_arn
# ============================================================
output "lbc_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller — used in Helm chart values"
  value       = aws_iam_role.lbc.arn
}

output "lbc_role_name" {
  description = "Name of the IRSA role for the AWS Load Balancer Controller"
  value       = aws_iam_role.lbc.name
}

output "lbc_policy_arn" {
  description = "ARN of the IAM policy attached to the LBC IRSA role"
  value       = aws_iam_policy.lbc.arn
}
