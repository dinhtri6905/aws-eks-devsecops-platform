# Infrastructure Architecture

## Overview

All AWS infrastructure is provisioned by Terraform and organized into
reusable modules. The environment layer (`environments/dev/`) consumes
these modules and wires their outputs together. No resource is created
outside of Terraform — the state of AWS always reflects what is in Git.

---

## AWS Region and Availability Zones

| Setting | Value |
|---|---|
| Region | ap-southeast-1 (Singapore) |
| Availability Zones | ap-southeast-1a, ap-southeast-1b |
| Multi-AZ (dev) | Subnets span 2 AZs; RDS Multi-AZ disabled to reduce cost |

---

## Network Design (VPC Module)

```
VPC: 10.0.0.0/16
|
+-- Public Subnet AZ-a: 10.0.1.0/24
|   +-- NAT Gateway (single, cost-optimized for dev)
|
+-- Public Subnet AZ-b: 10.0.2.0/24
|
+-- Private Subnet AZ-a: 10.0.11.0/24
|   +-- EKS Worker Nodes
|   +-- RDS PostgreSQL
|
+-- Private Subnet AZ-b: 10.0.12.0/24
    +-- EKS Worker Nodes
    +-- RDS Subnet Group (requires 2 AZs minimum)
```

**Why private subnets for worker nodes:**
Worker nodes have no public IP addresses. All outbound traffic routes
through the single NAT Gateway. This eliminates the attack surface of
direct internet access to compute nodes.

**Why a single NAT Gateway in dev:**
High availability NAT (one per AZ) costs approximately $65/month per
gateway. A single NAT Gateway reduces dev environment cost while the
architecture is identical in prod where HA NAT is enabled.

**EKS subnet tags:**
Public subnets carry `kubernetes.io/role/elb: 1` so the AWS Load
Balancer Controller can place internet-facing ALBs there.
Private subnets carry `kubernetes.io/role/internal-elb: 1` for
internal load balancers.

---

## Security Groups

Each component has a dedicated Security Group with the minimum required
ingress rules. Rules reference Security Group IDs rather than CIDRs
wherever possible, so rules remain correct even if IP addresses change.

| Security Group | Inbound Rules |
|---|---|
| EKS Control Plane | 443 from EKS Nodes SG |
| EKS Nodes | self (pod-to-pod), 10250 from Control Plane SG, 1025-65535 from Control Plane SG, 30000-32767 from ALB SG |
| ALB | 80 and 443 from 0.0.0.0/0 |
| RDS | 5432 from EKS Nodes SG only |

Rules are defined with `aws_security_group_rule` resources separate from
the `aws_security_group` resource to avoid circular dependency errors
between the control plane and node group security groups.

---

## EKS Cluster

| Setting | Value | Rationale |
|---|---|---|
| Kubernetes version | 1.33 | Latest stable at time of build |
| Node instance type | t3.medium | 2 vCPU / 4 GB RAM — sufficient for dev workloads |
| Node desired count | 2 | Minimum for pod scheduling across 2 AZs |
| Node min / max | 1 / 3 | Room to scale without over-provisioning |
| Node disk | 20 GiB gp3 | Enough for container images and ephemeral storage |
| AMI | AL2023_x86_64_STANDARD | Amazon Linux 2023 — latest generation |
| API endpoint | Public + Private | Public for developer access; private for in-cluster communication |
| Authentication | API_AND_CONFIG_MAP | Supports both IAM and RBAC-based access |

**Managed Node Groups** are used instead of self-managed nodes. AWS
handles node patching, AMI updates, and graceful draining during
upgrades. The `ignore_changes` lifecycle rule on `desired_size` prevents
Terraform from overriding the count managed by the Cluster Autoscaler.

**OIDC Provider** is created alongside the cluster. This is the
prerequisite for IRSA — every addon and workload that needs AWS API
access gets its own IAM role scoped to its specific ServiceAccount.

---

## EKS Addons

| Addon | Purpose | IRSA Required |
|---|---|---|
| vpc-cni | Pod networking — assigns VPC IPs to pods | No |
| coredns | Cluster DNS resolution for service discovery | No |
| kube-proxy | Network rules on each node | No |
| aws-ebs-csi-driver | Dynamic EBS volume provisioning for PVCs | Yes — scoped to `kube-system:ebs-csi-controller-sa` |

The EBS CSI Driver addon is required for Prometheus and Grafana to
provision `gp3` PersistentVolumeClaims for data storage.

---

## IAM Design

The platform follows a strict least-privilege IAM design. No component
uses static IAM credentials. Authentication to AWS APIs happens through:

1. **OIDC federation (GitHub Actions)** — CI/CD pipelines assume an IAM
   role via GitHub's OIDC token. No `AWS_ACCESS_KEY_ID` stored anywhere.

2. **IRSA (IAM Roles for Service Accounts)** — Each Kubernetes workload
   that needs AWS access has its own IAM role. The trust policy is scoped
   to the exact namespace and ServiceAccount name.

| Role | Used by | Key permissions |
|---|---|---|
| `eks-cluster-role` | EKS Control Plane | `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController` |
| `eks-node-group-role` | Worker Nodes | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore` |
| `ebs-csi-driver-role` | EBS CSI Driver | `AmazonEBSCSIDriverPolicy` |
| `aws-lbc-role` | AWS Load Balancer Controller | Custom policy — create/delete ALBs, manage target groups, security groups |

---

## Amazon ECR

Eleven repositories are provisioned — one per Online Boutique service.
Repository naming convention: `eks-devsecops-dev/<service-name>`.

| Setting | Value | Purpose |
|---|---|---|
| Image scanning | Enabled on push | Automatic CVE scanning via ECR Basic Scanning |
| Tag mutability | MUTABLE | Allows overwriting tags during development |
| Encryption | AES-256 | Server-side encryption at rest |
| Lifecycle policy — tagged | Keep last 10 `v*` images | Retain release versions |
| Lifecycle policy — untagged | Expire after 7 days | Remove CI build artifacts |

Repository policy allows pull-only access for the EKS Node Group IAM
role and full management access for the AWS account root. No
cross-account access is granted.

---

## Amazon RDS PostgreSQL

| Setting | Value | Rationale |
|---|---|---|
| Engine | PostgreSQL 15.7 | Latest stable PostgreSQL 15.x |
| Instance class | db.t3.micro | Cost-optimized for dev |
| Storage type | gp3 | 20% cheaper than gp2, IOPS independently scalable |
| Storage | 20 GiB (autoscales to 100 GiB) | Prevents manual intervention if data grows |
| Encryption | Enabled (AES-256) | Required for compliance |
| Multi-AZ | Disabled in dev | Enabled in prod |
| Publicly accessible | No | Reachable only from EKS nodes via Security Group |
| Backup retention | 7 days | Point-in-time recovery within one week |
| Performance Insights | Enabled (7 days) | Free tier — aids query debugging |
| Parameter group | Custom (postgres15) | Enables query logging, DDL logging, slow query threshold 1s |

---

## ALB (Load Balancer Controller)

The AWS Load Balancer Controller is deployed by ArgoCD (Wave 1) and
acts as an operator — it watches Kubernetes Ingress resources and
creates AWS ALBs to match. No ALB is provisioned by Terraform.

The Terraform `alb` module provisions only the IAM Policy and IRSA
Role that the controller needs to call AWS APIs. This follows the
separation of concerns between infrastructure (Terraform) and
Kubernetes operators (GitOps).

When the `frontend` Ingress is applied to the cluster, the controller:
1. Reads the Ingress annotations (`alb.ingress.kubernetes.io/*`)
2. Creates an internet-facing ALB in the public subnets
3. Creates a Target Group targeting the frontend pods directly (IP mode)
4. Configures health checks against `/_healthz`

---

## Terraform Module Dependency Graph

```
module.vpc
  |
  +-- module.security_group (needs vpc_id, vpc_cidr)
  |
  +-- module.eks (needs vpc_id, private_subnet_ids)
  |     |
  |     +-- module.alb (needs oidc_provider_arn, oidc_issuer_url)
  |
  +-- module.rds (needs private_subnet_ids, rds_sg_id)

module.iam
  |
  +-- module.eks (needs cluster_role_arn, node_group_role_arn)
  +-- module.ecr (needs eks_node_role_arn)
```

`module.ecr` and `module.vpc` are independent — Terraform creates them
in parallel, reducing total apply time.
