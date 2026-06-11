provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-eks-devsecops-platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "NguyenDinhTri"
    }
  }
}