# ============================================================
# VPC
# ============================================================
module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  single_nat_gateway   = var.single_nat_gateway
}

# ============================================================
# IAM
# ============================================================
module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment

  cluster_name = var.cluster_name
}

# ============================================================
# SECURITY GROUP
# ============================================================
module "security-group" {
  source = "../../modules/security-group"

  project_name = var.project_name
  environment  = var.environment

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr
}

# ============================================================
# EKS
# ============================================================


# ============================================================
# ECR
# ============================================================


# ============================================================
# RDS
# ============================================================


# ============================================================
# ALB
# ============================================================

