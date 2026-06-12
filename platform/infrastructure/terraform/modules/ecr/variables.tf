variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Image tag mutability: MUTABLE allows overwriting tags, IMMUTABLE prevents it"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable automatic vulnerability scanning when an image is pushed"
  type        = bool
  default     = true
}

variable "lifecycle_policy_enabled" {
  description = "Enable ECR lifecycle policy to automatically clean up old images"
  type        = bool
  default     = true
}

variable "tagged_image_keep_count" {
  description = "Number of tagged images to retain per repository"
  type        = number
  default     = 10
}

variable "untagged_image_expiry_days" {
  description = "Number of days before untagged images are automatically removed"
  type        = number
  default     = 7
}

variable "eks_node_role_arn" {
  description = "ARN of the EKS Node Group IAM Role — granted pull-only access to all repositories"
  type        = string
}
