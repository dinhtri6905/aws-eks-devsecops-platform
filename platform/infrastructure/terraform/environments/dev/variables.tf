# ============================================================
# GENERAL 
# ============================================================
variable "project_name" {
  description = "Project Name"
  type        = string
  default     = "eks-devsecops"
}

variable "environment" {
  description = "Deploy Environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}
