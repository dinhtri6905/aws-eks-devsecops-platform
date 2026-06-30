variable "aws_region" {
  description = "AWS region where the OIDC provider and IAM role will be created"
  type        = string
  default     = "ap-southeast-1"
}

variable "github_org" {
  description = "GitHub organization name or personal username (e.g. my-org)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the org prefix (e.g. my-repo)"
  type        = string
}