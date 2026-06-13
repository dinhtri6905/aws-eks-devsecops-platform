# environments/dev

Terraform configuration for the **dev** environment of the **Cloud-Native Secure GitOps Platform on AWS EKS**.

This environment provisions the complete AWS infrastructure required to run the platform — networking, security, EKS, container registry, database, and the IAM/IRSA foundations for the GitOps layer — before any Kubernetes workloads are deployed. Once Terraform completes, ArgoCD takes over and continuously synchronizes all platform services and applications from Git.

---

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                       AWS ap-southeast-1                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   VPC  10.0.0.0/16                       │   │
│  │                                                          │   │
│  │  ┌─────────────────────┐ ┌─────────────────────────┐     │   │
│  │  │  Public Subnet AZ-a │ │  Public Subnet AZ-b     │     │   │
│  │  │  10.0.1.0/24        │ │  10.0.2.0/24            │     │   │
│  │  │  [NAT Gateway]      │ │                         │     │   │
│  │  └─────────────────────┘ └─────────────────────────┘     │   │
│  │                                                          │   │
│  │  ┌─────────────────────┐ ┌─────────────────────────┐     │   │
│  │  │  Private Subnet AZ-a│ │  Private Subnet AZ-b    │     │   │
│  │  │  10.0.11.0/24       │ │  10.0.12.0/24           │     │   │
│  │  │  [EKS Nodes]        │ │  [EKS Nodes] [RDS]      │     │   │
│  │  └─────────────────────┘ └─────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│ [ECR Repositories]   [IAM Roles + IRSA]   [OIDC Provider]       │
└─────────────────────────────────────────────────────────────────┘
```

### End-to-End Platform Flow

```text
Terraform (Infrastructure Provisioning)
│
├── VPC
├── Security Groups
├── IAM + IRSA
├── EKS
├── ECR
├── RDS PostgreSQL
└── ALB (IAM/IRSA for AWS Load Balancer Controller)
└── ArgoCD Bootstrap
       │
       ▼
ArgoCD Root Application (App of Apps)
       │
       ├── Platform Services
       │      ├── Metrics Server
       │      └── AWS Load Balancer Controller
       │
       ├── Security
       │      ├── OPA Gatekeeper
       │      └── Falco
       │
       ├── Observability
       │      ├── Prometheus
       │      └── Grafana
       │
       └── Applications
              └── Online Boutique
```

> **Note on ArgoCD bootstrap:** ArgoCD installation and the Root Application bootstrap are handled outside this Terraform configuration (manually, via the `bootstrap-argocd` step in the GitHub Actions `terraform-apply` workflow, or via a separate `argocd-bootstrap` module/script). This `environments/dev` configuration provisions the **infrastructure only** — VPC through ALB IAM/IRSA — so that the cluster is ready for ArgoCD to take over.

---

## Prerequisites

### Required Tools

Ensure the following tools are installed and available in your `$PATH` before proceeding:

| Tool | Minimum Version | Install Guide |
|---|---|---|
| Terraform | `>= 1.10.0` | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | `>= 2.x` | [docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| kubectl | `>= 1.30` | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| helm | `>= 3.x` | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) *(optional — used for manual chart inspection)* |

> The **AWS Provider `>= 6.0.0`** is declared directly in `versions.tf` and pulled automatically by `terraform init`. You do not need to install it separately.

Verify tool versions:

```bash
terraform version
aws --version
kubectl version --client
helm version   # optional
```

### Required AWS Permissions

The IAM principal (user or assumed role) running Terraform must have sufficient permissions to create and manage:

- VPC, Subnets, Route Tables, Internet/NAT Gateways
- Security Groups
- IAM Roles, Policies, and OIDC Providers
- EKS Clusters and Managed Node Groups
- ECR Repositories
- RDS Instances and Subnet Groups
- KMS Key usage (for state encryption)
- S3 and DynamoDB (for remote state)

For dev environments, attaching **`AdministratorAccess`** is the easiest option. For production, scope down to least-privilege using the resource types above.

### Bootstrap Resources

The following resources must already exist **before** running `terraform init`:

| Resource | Purpose |
|---|---|
| S3 Bucket | Remote state storage |
| DynamoDB Table | State locking (prevents concurrent applies) |
| KMS Key | Server-side encryption of the state file |

Configure `backend.tf` with the names of those resources before running `terraform init`.

### AWS Identity Verification

Verify your AWS identity and confirm the correct account/region before starting:

```bash
# Configure credentials if not already set
aws configure

# Confirm identity
aws sts get-caller-identity

# Confirm target region (should match var.aws_region)
aws configure get region
```

---

## Modules

| Module | What it provisions |
|---|---|
| `vpc` | VPC, public/private subnets (2 AZs), Internet Gateway, NAT Gateway, route tables |
| `security-group` | Security Groups for EKS Control Plane, EKS Nodes, ALB, and RDS |
| `iam` | EKS Cluster Role, EKS Node Group Role, IAM policy attachments |
| `eks` | EKS Cluster, Managed Node Group, OIDC Provider, EBS CSI Driver |
| `ecr` | ECR repositories for all 11 Online Boutique microservices |
| `alb` | IAM Policy + IRSA Role for the AWS Load Balancer Controller |
| `rds` | PostgreSQL RDS instance, DB Subnet Group, Parameter Group |

> The AWS Load Balancer Controller, ArgoCD, Prometheus, Grafana, OPA Gatekeeper, and Falco are **not** created by these modules — Terraform only creates the IAM/IRSA roles they need. The workloads themselves are deployed by ArgoCD (see [Platform Tools — Deployed via GitOps](#platform-tools--deployed-via-gitops-not-terraform)).

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

### 4. Format & validate

```bash
terraform fmt -recursive
terraform validate
```

### 5. Review the plan

```bash
terraform plan -out=tfplan
```

### 6. Apply

```bash
terraform apply tfplan
```

Or, without a saved plan:

```bash
terraform apply
```

### 7. Connect to the cluster

After apply completes, run the kubeconfig command from the outputs:

```bash
terraform output -raw kubeconfig_command | bash
```

Verify connectivity:

```bash
kubectl get nodes
```

### 8. Destroy (when no longer needed)

```bash
terraform destroy
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

```text
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

The following tools are **not** provisioned by this Terraform configuration. Once the infrastructure above is ready, they are deployed into the EKS cluster via ArgoCD using the **App of Apps** pattern:

| Tool | Purpose | Requires Terraform output |
|---|---|---|
| AWS Load Balancer Controller | Dynamic ALB provisioning for Ingress | `lbc_role_arn` |
| ArgoCD | GitOps continuous delivery (Root Application / App of Apps) | `kubeconfig_command` |
| Metrics Server | Resource metrics for `kubectl top` and HPA | — |
| Prometheus | Metrics collection | — |
| Grafana | Dashboards and visualization | — |
| OPA Gatekeeper | Policy-as-Code enforcement (admission control) | — |
| Falco | Runtime threat detection | — |
| Online Boutique | Demonstration microservices application | `ecr_repository_urls` |

After Terraform finishes provisioning the cluster, ArgoCD's Root Application continuously synchronizes the Git repository and manages all of the above platform services and applications — Platform Services (Metrics Server, AWS Load Balancer Controller), Security (OPA Gatekeeper, Falco), Observability (Prometheus, Grafana), and Applications (Online Boutique).

---

## Security Notes

- Worker nodes run in **private subnets** only — no direct internet access.
- RDS is **not publicly accessible** — reachable only from EKS nodes via Security Group rules.
- EKS API server has **both public and private endpoint** enabled for dev. For prod, disable public access.
- All IAM roles follow **least privilege** — each role has only the minimum permissions required, including dedicated IRSA roles for EBS CSI Driver and AWS Load Balancer Controller.
- ECR repositories allow **pull-only** for EKS nodes and full management for the account root.
- EBS volumes and RDS storage are **encrypted at rest** with AES-256.
- `db_password` is marked `sensitive = true` — never printed in plan or apply output, and must be supplied via `TF_VAR_db_password`.
- Security controls beyond the infrastructure layer (admission control, runtime threat detection) are enforced by **OPA Gatekeeper** and **Falco**, deployed via ArgoCD.

---

## Environment

```text
Environment : Development
Region      : ap-southeast-1
```

---

## Notes

- Infrastructure provisioning is managed by **Terraform**.
- Kubernetes platform services are managed by **ArgoCD**.
- Security controls are enforced through **OPA Gatekeeper** and **Falco**.
- Monitoring and observability are provided by **Prometheus** and **Grafana**.
- Application delivery follows a **GitOps** workflow.
- The **Online Boutique** application serves as the demonstration microservices workload for the platform.
- The architecture follows the **AWS Well-Architected Framework** and **Terraform best practices**.

---

## Cost Considerations (Dev Environment)

This configuration is intentionally optimized for **low cost** in development. Key cost-saving choices:

| Resource | Choice | Cost Impact |
|---|---|---|
| NAT Gateway | Single NAT (`single_nat_gateway = true`) | ~$32/month vs ~$64/month for HA |
| EKS Nodes | `t3.medium` × 2 (desired) | ~$60/month for 2 nodes |
| RDS | `db.t3.micro`, single-AZ, no read replica | ~$15/month |
| EKS Control Plane | 1 cluster | Fixed ~$72/month (AWS-managed) |

> **Estimated total: ~$180–$220/month** depending on data transfer and storage usage. Run `terraform destroy` when the environment is no longer needed to avoid ongoing charges.

---

## Troubleshooting

### `terraform init` fails — backend not found

Ensure the S3 bucket, DynamoDB table, and KMS key exist in the target region and that your IAM principal has access to them. Double-check the values in `backend.tf`.

### `terraform apply` fails on EKS

Kubernetes version `1.33` may not be available in all regions. Check available versions:

```bash
aws eks describe-addon-versions --region ap-southeast-1 \
  --query 'addons[0].addonVersions[].addonVersion' --output table
```

### `kubectl get nodes` returns no output

Re-run the kubeconfig update and verify the node group is `ACTIVE`:

```bash
terraform output -raw kubeconfig_command | bash
aws eks describe-nodegroup \
  --cluster-name $(terraform output -raw cluster_name) \
  --nodegroup-name <nodegroup-name> \
  --region ap-southeast-1 \
  --query 'nodegroup.status'
```

### RDS password rejected at apply time

`TF_VAR_db_password` is not persisted between shell sessions. Re-export before every `terraform apply`:

```bash
export TF_VAR_db_password="<your-secure-password>"
terraform apply
```

### Pods stuck in `Pending` — insufficient node capacity

The default node group uses `t3.medium` (2 vCPU / 4 GiB RAM). If the full stack exceeds capacity, scale up temporarily:

```bash
terraform apply -var="node_desired_size=3"
```

---

## CI/CD Integration (GitHub Actions)

This environment is designed to be applied via the `terraform-apply` GitHub Actions workflow. The workflow handles:

1. `terraform init` with the remote backend
2. `terraform fmt` and `terraform validate` checks
3. `terraform plan` with the plan saved as a workflow artifact
4. `terraform apply` on the saved plan (manual approval gate for production)
5. `bootstrap-argocd` step — installs ArgoCD and applies the Root Application after infrastructure is ready

Required GitHub Actions secrets:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM access key with deployment permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret key |
| `TF_VAR_db_password` | RDS master password |

> For production pipelines, prefer **OIDC-based authentication** (IAM Roles for GitHub Actions) over static access keys to eliminate long-lived credentials.
