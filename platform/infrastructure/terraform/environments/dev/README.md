# environments/dev

Terraform configuration for the **dev** environment of the Cloud-Native Secure GitOps Platform on AWS EKS.

This environment provisions all AWS infrastructure required to run the platform before any Kubernetes workloads are deployed.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS ap-southeast-1                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   VPC  10.0.0.0/16                       │   │
│  │                                                          │   │
│  │  ┌─────────────────────┐  ┌─────────────────────────┐   │   │
│  │  │  Public Subnet AZ-a │  │  Public Subnet AZ-b     │   │   │
│  │  │  10.0.1.0/24        │  │  10.0.2.0/24            │   │   │
│  │  │  [NAT Gateway]      │  │                         │   │   │
│  │  └─────────────────────┘  └─────────────────────────┘   │   │
│  │                                                          │   │
│  │  ┌─────────────────────┐  ┌─────────────────────────┐   │   │
│  │  │  Private Subnet AZ-a│  │  Private Subnet AZ-b    │   │   │
│  │  │  10.0.11.0/24       │  │  10.0.12.0/24           │   │   │
│  │  │  [EKS Nodes]        │  │  [EKS Nodes] [RDS]      │   │   │
│  │  └─────────────────────┘  └─────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  [ECR Repositories]   [IAM Roles]   [OIDC Provider]             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Requirement | Version |
|---|---|
| Terraform | >= 1.10.0 |
| AWS Provider | >= 6.0.0 |
| AWS CLI | >= 2.x |

The following bootstrap resources must already exist before running this configuration:

- S3 bucket for Terraform remote state
- DynamoDB table for state locking
- KMS key for state encryption

Configure `backend.tf` with the names of those resources before running `terraform init`.

---

## Modules

| Module | What it provisions |
|---|---|
| `vpc` | VPC, public/private subnets, IGW, NAT Gateway, route tables |
| `iam` | EKS Cluster Role, EKS Node Group Role, IAM policy attachments |
| `security_group` | Security Groups for EKS Control Plane, EKS Nodes, ALB, RDS |
| `eks` | EKS Cluster 1.33, Managed Node Group, OIDC Provider, EBS CSI Driver |
| `ecr` | ECR repositories for all Online Boutique microservices |
| `alb` | IAM Policy + IRSA Role for AWS Load Balancer Controller |
| `rds` | PostgreSQL 15 RDS instance, DB Subnet Group, Parameter Group |

---

## Quick Start

### 1. Configure the remote backend

Edit `backend.tf` and fill in the S3 bucket, DynamoDB table, and KMS key created by the bootstrap:

```hcl
terraform {
  backend "s3" {
    bucket         = "<your-state-bucket-name>"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "<your-lock-table-name>"
    kms_key_id     = "<your-kms-key-arn>"
  }
}
```

### 2. Set the database password

The `db_password` variable is sensitive and must never be hardcoded. Set it via an environment variable before running any Terraform commands:

```bash
export TF_VAR_db_password="<your-secure-password>"
```

### 3. Initialize

```bash
terraform init
```

### 4. Review the plan

```bash
terraform plan
```

### 5. Apply

```bash
terraform apply
``` 

### 6. Connect to the cluster

After apply completes, run the kubeconfig command from the outputs:

```bash
terraform output -raw kubeconfig_command | bash
```

Verify connectivity:

```bash
kubectl get nodes
```

---

## Input Variables

### General

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | `string` | `eks-devsecops` | Project name used in all resource names |
| `environment` | `string` | `dev` | Deployment environment |
| `aws_region` | `string` | `ap-southeast-1` | AWS region |

### VPC

| Variable | Type | Default | Description |
|---|---|---|---|
| `vpc_cidr` | `string` | `10.0.0.0/16` | VPC CIDR block |
| `public_subnet_cidrs` | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | Public subnet CIDRs |
| `private_subnet_cidrs` | `list(string)` | `["10.0.11.0/24", "10.0.12.0/24"]` | Private subnet CIDRs |
| `availability_zones` | `list(string)` | `["ap-southeast-1a", "ap-southeast-1b"]` | Availability Zones |
| `single_nat_gateway` | `bool` | `true` | Single NAT Gateway (cost-optimized for dev) |

### EKS

| Variable | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | `string` | `eks-devsecops-dev-cluster` | EKS cluster name |
| `kubernetes_version` | `string` | `1.33` | Kubernetes version |
| `node_instance_types` | `list(string)` | `["t3.medium"]` | EC2 instance types for worker nodes |
| `node_desired_size` | `number` | `2` | Desired number of nodes |
| `node_min_size` | `number` | `1` | Minimum number of nodes |
| `node_max_size` | `number` | `3` | Maximum number of nodes |
| `node_disk_size` | `number` | `20` | EBS root volume size (GiB) |

### ECR

| Variable | Type | Default | Description |
|---|---|---|---|
| `ecr_repository_names` | `list(string)` | 11 Online Boutique services | List of ECR repository names |

### RDS

| Variable | Type | Default | Description |
|---|---|---|---|
| `db_identifier` | `string` | `eks-devsecops-dev-postgres` | RDS instance identifier |
| `db_name` | `string` | `appdb` | Initial database name |
| `db_username` | `string` | `dbadmin` | Master username |
| `db_password` | `string` | **required** | Master password — set via `TF_VAR_db_password` |
| `db_instance_class` | `string` | `db.t3.micro` | RDS instance class |
| `db_engine_version` | `string` | `15.7` | PostgreSQL engine version |
| `multi_az` | `bool` | `false` | Multi-AZ deployment |
| `backup_retention_period` | `number` | `7` | Backup retention in days |

---

## Outputs

### VPC

| Output | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `internet_gateway_id` | ID of the Internet Gateway |
| `nat_gateway_ids` | List of NAT Gateway IDs |
| `nat_gateway_public_ips` | Public IPs of NAT Gateways |
| `public_route_table_id` | ID of the public route table |
| `private_route_table_ids` | List of private route table IDs |

### IAM

| Output | Description |
|---|---|
| `eks_cluster_role_arn` | ARN of the EKS Cluster IAM Role |
| `eks_cluster_role_name` | Name of the EKS Cluster IAM Role |
| `eks_node_group_role_arn` | ARN of the EKS Node Group IAM Role |
| `eks_node_group_role_name` | Name of the EKS Node Group IAM Role |

### Security Groups

| Output | Description |
|---|---|
| `eks_control_plane_sg_id` | Security Group ID for EKS Control Plane |
| `eks_nodes_sg_id` | Security Group ID for EKS Worker Nodes |
| `alb_sg_id` | Security Group ID for ALB |
| `rds_sg_id` | Security Group ID for RDS |

### EKS

| Output | Description |
|---|---|
| `cluster_name` | Name of the EKS cluster |
| `cluster_endpoint` | Kubernetes API server endpoint |
| `cluster_ca_certificate` | Base64-encoded CA certificate (sensitive) |
| `cluster_version` | Kubernetes version |
| `oidc_provider_arn` | OIDC provider ARN — used for IRSA roles |
| `oidc_issuer_url` | OIDC issuer URL |
| `ebs_csi_driver_role_arn` | IRSA role ARN for EBS CSI Driver |
| `kubeconfig_command` | AWS CLI command to update kubeconfig |

### ECR

| Output | Description |
|---|---|
| `ecr_repository_urls` | Map of service name to ECR repository URL |
| `ecr_repository_arns` | Map of service name to ECR repository ARN |
| `ecr_registry_id` | AWS account ID of the ECR registry |

### RDS

| Output | Description |
|---|---|
| `db_instance_id` | RDS instance identifier |
| `db_instance_endpoint` | Connection endpoint in `host:port` format (sensitive) |
| `db_instance_address` | RDS hostname (sensitive) |
| `db_instance_port` | RDS port |
| `db_name` | Name of the initial database |

### ALB

| Output | Description |
|---|---|
| `lbc_role_arn` | IRSA role ARN for AWS Load Balancer Controller |
| `lbc_policy_arn` | IAM policy ARN for AWS Load Balancer Controller |

---

## Useful Commands

```bash
# View all outputs
terraform output

# Get a specific sensitive output
terraform output -raw db_instance_address

# Update kubeconfig
terraform output -raw kubeconfig_command | bash

# Get LBC role ARN for Helm values
terraform output -raw lbc_role_arn

# Get ECR URL for a specific service
terraform output -json ecr_repository_urls | jq -r '.frontend'

# Destroy the environment
terraform destroy
```

---

## Module Dependency Graph

```
module.vpc    ─────────────────────────────────► module.security_group
              └──────────────────────────────────────────┐
                                                         │
module.iam    ──────────────────────────────────────┐    │
              └──► module.ecr                       │    │
                                                    ▼    ▼
                                               module.eks
                                                    │
                                                    ▼
                                               module.alb

module.vpc    ──► module.rds ◄── module.security_group
```

---

## Platform Tools — Deployed via GitOps (not Terraform)

The following tools are **not** provisioned by this Terraform configuration. They are deployed into the EKS cluster via ArgoCD after the infrastructure is ready:

| Tool | Purpose | Requires Terraform output |
|---|---|---|
| AWS Load Balancer Controller | Dynamic ALB provisioning | `lbc_role_arn` |
| ArgoCD | GitOps continuous delivery | — |
| Prometheus | Metrics collection | — |
| Grafana | Dashboards and visualization | — |
| OPA Gatekeeper | Policy-as-Code enforcement | — |
| Falco | Runtime threat detection | — |

---

## Security Notes

- Worker nodes run in **private subnets** only — no direct internet access.
- RDS is **not publicly accessible** — reachable only from EKS nodes via Security Group rules.
- EKS API server has **both public and private endpoint** enabled for dev. For prod, disable public access.
- All IAM roles follow **least privilege** — each role has only the minimum permissions required.
- ECR repositories allow **pull-only** for EKS nodes and full management for the account root.
- EBS volumes and RDS storage are **encrypted at rest** with AES-256.
- `db_password` is marked `sensitive = true` — never printed in plan or apply output.
