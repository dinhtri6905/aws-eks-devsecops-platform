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
module "eks" {
  source = "../../modules/eks"

  project_name = var.project_name
  environment  = var.environment

  cluster_name = var.cluster_name

  kubernetes_version = var.kubernetes_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_sg_id      = module.security_group.eks_control_plane_sg_id
  node_sg_id         = module.security_group.eks_nodes_sg_id

  cluster_role_arn    = module.iam.eks_cluster_role_arn
  node_group_role_arn = module.iam.eks_node_group_role_arn

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
}

# ============================================================
# ECR
# ============================================================
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment

  repository_names = var.ecr_repository_names

  image_tag_mutability       = var.image_tag_mutability
  scan_on_push               = var.scan_on_push
  tagged_image_keep_count    = var.tagged_image_keep_count
  untagged_image_expiry_days = var.untagged_image_expiry_days

  eks_node_role_arn = module.iam.eks_node_group_role_arn
}

# ============================================================
# RDS
# ============================================================
module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_group.rds_sg_id

  db_identifier = var.db_identifier
  db_name       = var.db_name
  db_username   = var.db_username
  db_password   = var.db_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage

  db_engine_version = var.db_engine_version
  db_instance_class = var.db_instance_class

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  deletion_protection     = false # In production, change it to "true".
  skip_final_snapshot     = true  # In production, change it to "false".
}

# ============================================================
# ALB
# ============================================================

