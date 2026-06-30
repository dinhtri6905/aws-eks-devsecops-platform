terraform {
  backend "s3" {
    bucket         = "eks-devsecops-terraform-state-ndt"
    key            = "dev/terraform.tfstate" # đường dẫn path file state bên trong S3 bucket.
    region         = "ap-southeast-1"
    dynamodb_table = "eks-devsecops-terraform-lock-ndt"
    encrypt        = true
  }
}