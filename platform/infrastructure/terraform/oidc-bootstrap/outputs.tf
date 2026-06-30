output "role_arn" {
  description = "IAM Role ARN — add this as GitHub Secret: AWS_DEV_ROLE_ARN"
  value       = aws_iam_role.github_actions_terraform_dev.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC Identity Provider created in IAM"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "aws_account_id" {
  description = "AWS account ID where the resources were provisioned"
  value       = data.aws_caller_identity.current.account_id
}