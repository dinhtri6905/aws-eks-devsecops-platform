# Cloud-Native Secure GitOps Platform on AWS EKS

A production-grade **DevSecOps platform** on AWS EKS that embeds security at every layer of the software delivery lifecycle — from infrastructure policy gates to runtime threat detection. Security is not an afterthought; it is enforced at IaC scan time, image build time, admission time, and runtime.

The platform uses **Online Boutique** (Google's open-source microservices demo) as the demonstration workload — 11 services across Go, Python, Node.js, Java, and C# — deployed and managed entirely through GitOps.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Solution Architecture](#2-solution-architecture)
3. [Key Features](#3-key-features)
4. [Architecture Decisions](#4-architecture-decisions)
5. [Repository Structure](#5-repository-structure)
6. [Infrastructure Design](#6-infrastructure-design)
7. [GitOps Workflow](#7-gitops-workflow)
8. [CI/CD Platform](#8-cicd-platform)
9. [GitHub Secrets & Environments](#9-github-secrets--environments)
10. [Security Architecture](#10-security-architecture)
11. [Observability Architecture](#11-observability-architecture)
12. [Online Boutique Microservices](#12-online-boutique-microservices)
13. [Deployment Guide](#13-deployment-guide)
14. [Validation & Testing](#14-validation--testing)
15. [Disaster Recovery Strategy](#15-disaster-recovery-strategy)
16. [Troubleshooting](#16-troubleshooting)
17. [Future Enhancements](#17-future-enhancements)
18. [References](#18-references)

---

## 1. Project Overview

This platform demonstrates how to build a **secure, automated, and observable** Kubernetes delivery system on AWS — the kind of foundation that a platform engineering team would build for multiple development teams to operate on top of.

### Problem Statement

Modern microservices teams face three compounding challenges:

- **Security drift** — configurations diverge from policy over time, vulnerabilities accumulate in images, and runtime threats go undetected
- **Manual toil** — infrastructure changes require human coordination, deployments are error-prone, and rollbacks are slow
- **Observability gaps** — without unified metrics, dashboards, and alerting, incidents are detected by end users before engineers

### Solution

This platform addresses all three through a layered approach:

```
Security-first design:
  IaC scanning  →  Image scanning  →  Admission control  →  Runtime detection

Automation:
  Git push  →  CI  →  OPA gate  →  CD  →  ArgoCD sync  →  Live cluster

Observability:
  Prometheus scrapes  →  Grafana dashboards  →  Alertmanager notifications
```

### Scope

| Layer | Technology | Responsibility |
|---|---|---|
| Infrastructure | Terraform on AWS | VPC, EKS, ECR, RDS, ALB, IAM |
| Platform | ArgoCD + Kustomize | GitOps delivery, App of Apps |
| Security (static) | OPA Rego | Terraform plan policy gate |
| Security (admission) | OPA Gatekeeper | Kubernetes admission control |
| Security (runtime) | Falco | Syscall-level threat detection |
| Observability | kube-prometheus-stack | Metrics, dashboards, alerting |
| CI/CD | GitHub Actions | Five workflows covering infra + app |
| Application | Online Boutique | 11-service gRPC microservices demo |

---

## 2. Solution Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                           │
│                                                                     │
│  platform/infrastructure/terraform/   ← Infrastructure as Code     │
│  platform/gitops/                     ← GitOps manifests           │
│  microservices-application/           ← Application source code    │
│  .github/workflows/                   ← CI/CD automation           │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions                               │
│                                                                     │
│  terraform-ci  ──►  terraform-cd (plan → OPA gate → apply)         │
│                                                ↓                   │
│  app-ci        ──►  app-cd (build → scan → push ECR → update Git)  │
└────────────────────────────┬────────────────────────────────────────┘
                             │ terraform apply
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS (ap-southeast-1)                         │
│                                                                     │
│  VPC 10.0.0.0/16                                                    │
│  ├── Public Subnets (ALB, NAT GW)                                   │
│  └── Private Subnets                                                │
│        ├── EKS Managed Node Group (t3.medium × 2)                   │
│        └── RDS PostgreSQL 15.7                                      │
│                                                                     │
│  ECR (11 repositories)      Amazon CloudWatch Logs                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼ (ArgoCD bootstrap via Terraform)
┌─────────────────────────────────────────────────────────────────────┐
│                     Amazon EKS (Kubernetes 1.33)                    │
│                                                                     │
│  argocd/          ArgoCD — GitOps controller                        │
│  kube-system/     Metrics Server, AWS Load Balancer Controller      │
│  gatekeeper-system/ OPA Gatekeeper (7 policies)                    │
│  falco/           Falco runtime threat detection                    │
│  monitoring/      Prometheus, Grafana, Alertmanager                 │
│  online-boutique/ 11 microservices + Redis + load generator        │
└─────────────────────────────────────────────────────────────────────┘
```

### Deployment Flow

```
Developer pushes to feature/**
          │
          ▼
  app-ci / terraform-ci   ← Static analysis, scanning, validation
          │
          │  PR approved → merge to main
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
terraform-cd   app-cd
    │               │
    │ plan          │ build per changed service
    │ opa-gate      │ Trivy image scan
    │ apply         │ push SHA tag to ECR
    │               │ kustomize edit set image
    ▼               │ git commit → push
AWS infra       ────┘
updated             │
                    ▼
            ArgoCD detects diff
                    │
                    ▼
            kustomize build overlay
                    │
                    ▼
            kubectl apply (server-side)
                    │
                    ▼
            Argo Rollouts blue/green cutover → traffic switches to green
```

### Sync Wave Ordering

ArgoCD deploys components in strict wave order to prevent admission webhooks from blocking their own installation and to ensure dependencies are ready before dependents start.

```
wave 1  ──  platform-services    Metrics Server, AWS Load Balancer Controller, Argo Rollouts
wave 2  ──  security             OPA Gatekeeper (+ 7 policies), Falco
wave 3  ──  observability        Prometheus, Grafana, Alertmanager
wave 4  ──  online-boutique      11 microservices as Rollout resources (blue/green)
```

---

## 3. Key Features

### Infrastructure as Code
- All AWS resources defined in modular Terraform — VPC, EKS, ECR, RDS, IAM, ALB
- Remote state in S3 with DynamoDB locking and KMS encryption
- OPA Rego policy gate between `terraform plan` and `terraform apply`
- Separate `bootstrap` module for one-time backend provisioning

### GitOps Delivery
- ArgoCD App of Apps pattern — one Root Application manages all child Applications
- Sync waves enforce deployment order across platform layers
- `selfHeal: true` reverts any out-of-band cluster changes to Git state
- Separate `dev` and `prod` Kustomize overlays for environment-specific configuration
- **Blue/Green deployments** via Argo Rollouts — instant cutover, instant rollback, zero user impact

### Security Across the Full Lifecycle
- Gitleaks secret scanning on every commit (hard gate)
- Trivy filesystem scan on source code before image build
- OPA Rego gates on Terraform plan — 3 policy files covering security, networking, compliance
- Trivy image scan — CRITICAL CVEs block ECR push
- OPA Gatekeeper — 7 admission policies enforced on every Pod
- Falco — kernel-level runtime threat detection on every node
- ECR `scan_on_push = true` — images scanned on arrival

### Observability
- Prometheus scrapes kube-state-metrics, node-exporter, ArgoCD, Gatekeeper, Falco, and Online Boutique services
- 3 custom Grafana dashboards — cluster overview, node metrics, application metrics
- AlertManager rules for high CPU, high memory, and pod restart loops
- ServiceMonitor resources for automatic target discovery
- RDS Performance Insights enabled (7-day retention, free tier)
- EKS control plane logs shipped to CloudWatch (audit, authenticator, api, controllerManager, scheduler)

### CI/CD Automation
- 5 GitHub Actions workflows covering infrastructure and application tracks
- OIDC-based AWS authentication — no long-lived access keys
- Matrix builds — changed services detected automatically via `git diff`, built in parallel
- Slack notifications on every pipeline outcome

---

## 4. Architecture Decisions

### ADR-001: Single Repository (Mono-repo)

**Decision:** All infrastructure code, GitOps manifests, and application source code live in one repository.

**Rationale:** Reduces cross-repo coordination overhead for a single-team project. Changes spanning Terraform, Kustomize, and application code can be reviewed and merged atomically. A mono-repo is appropriate at this scale; a multi-repo setup is worth considering when multiple teams own separate services.

**Trade-off:** Repository size grows over time; CODEOWNERS files become important for access control.

---

### ADR-002: ArgoCD App of Apps Pattern

**Decision:** A single Root Application (created by Terraform) watches `platform/gitops/argocd/applications/` and manages four child Applications.

**Rationale:** Keeps ArgoCD bootstrapping in Terraform (infrastructure concern) while keeping all subsequent application definitions in Git (GitOps concern). Adding a new platform component requires only a new YAML file in `applications/` — no Terraform change.

**Trade-off:** Root Application is still managed by Terraform state. Deleting it via `terraform destroy` cascades to all child Applications.

---

### ADR-003: Kustomize over Helm for Application Manifests

**Decision:** Online Boutique is deployed via Kustomize overlays, not Helm.

**Rationale:** Online Boutique has no upstream Helm chart. Kustomize provides sufficient flexibility for dev/prod differences (replica counts, resource limits, config patches) without introducing templating complexity.

**Trade-off:** Helm's `helm rollback` is not available. Rollback is achieved by reverting the image tag commit in Git and letting ArgoCD re-sync.

---

### ADR-004: Helm for Platform Services (via Kustomize `helmCharts`)

**Decision:** Metrics Server, AWS Load Balancer Controller, OPA Gatekeeper, and kube-prometheus-stack are installed via Helm charts, referenced from Kustomize `helmCharts` blocks.

**Rationale:** These are established Helm-distributed projects with well-maintained charts and values. Using `helmCharts` in Kustomize keeps everything under ArgoCD's GitOps control without requiring a separate Helm operator.

**Trade-off:** Requires ArgoCD to have the `--enable-helm` flag or Kustomize helm plugin available. Helm chart pulls happen at sync time from the upstream chart repos.

---

### ADR-005: OPA Rego Policy Gate on Terraform Plan

**Decision:** `terraform plan` output is exported as JSON and evaluated against three Rego files before `terraform apply` is permitted.

**Rationale:** Catches infrastructure misconfigurations (open security groups, unencrypted RDS, missing tags) before they reach AWS — significantly cheaper to fix at plan time than after apply.

**Trade-off:** OPA evaluation adds ~30 seconds to the CD pipeline. Policy files must be maintained alongside the Terraform code they govern.

---

### ADR-006: Single NAT Gateway in Dev, Per-AZ in Prod

**Decision:** `single_nat_gateway = true` in dev; `false` in prod.

**Rationale:** A single NAT Gateway reduces dev costs by ~$32/month. In production, per-AZ NAT Gateways eliminate the single point of failure and reduce cross-AZ data transfer costs for EKS nodes.

**Trade-off:** If the single NAT Gateway's AZ has an outage in dev, all private subnet egress is lost. Acceptable for a non-production environment.

---

### ADR-007: IRSA over Node IAM Roles for AWS Service Access

**Decision:** AWS Load Balancer Controller and EBS CSI Driver use IAM Roles for Service Accounts (IRSA) rather than node-level IAM policies.

**Rationale:** IRSA grants permissions at the pod level rather than the node level — a compromised pod cannot use the full node role. Aligns with least-privilege.

**Trade-off:** Requires an OIDC provider on the EKS cluster (provisioned by the `eks` module) and a separate IAM role per controller.

---

### ADR-008: Blue/Green Deployment Strategy via Argo Rollouts

**Decision:** Online Boutique services use Blue/Green deployment managed by Argo Rollouts, replacing the default Kubernetes `RollingUpdate` strategy.

**Rationale:** Blue/Green provides instant, zero-risk cutover — the new version (green) is fully provisioned and health-checked before any production traffic is shifted. If the green stack fails health checks, the blue stack continues serving traffic with zero impact to users. This is significantly safer than Rolling Update, which gradually replaces pods and can expose users to a broken version during the rollout window.

**How it works:**
- Argo Rollouts creates and manages two ReplicaSets: `blue` (active) and `green` (preview)
- The green stack is brought up to full replica count before any traffic switch
- ArgoCD syncs the Rollout manifest; Argo Rollouts controller executes the strategy
- After the `autoPromotionSeconds` window (or manual approval in prod), traffic switches instantly via Service selector patch
- Rollback is a single `kubectl argo rollouts undo` command — traffic returns to blue within seconds

**Trade-off:** Requires running two full replica sets simultaneously during the switchover window, doubling compute cost temporarily. In dev (1 replica per service), this is negligible. In prod, size nodes accordingly.

---

## 5. Repository Structure

```
aws-eks-devsecops-platform/
│
├── .github/
│   └── workflows/
│       ├── terraform-ci.yaml           # Terraform static analysis
│       ├── terraform-cd.yaml           # Terraform plan → OPA gate → apply
│       ├── check-scan.yaml             # Scheduled nightly deep security scan
│       ├── app-ci.yaml                 # Application CI
│       └── app-cd.yaml                 # Application CD
│
├── microservices-application/
│   └── online-boutique/
│       ├── protos/                     # Shared gRPC proto definitions
│       └── src/
│           ├── adservice/              # Java  — contextual ads
│           ├── cartservice/            # C#    — cart state (Redis-backed)
│           ├── checkoutservice/        # Go    — order orchestration
│           ├── currencyservice/        # Node  — currency conversion
│           ├── emailservice/           # Python — email confirmation
│           ├── frontend/               # Go    — HTTP/web UI
│           ├── loadgenerator/          # Python (Locust) — load simulation
│           ├── paymentservice/         # Node  — mock payment
│           ├── productcatalogservice/  # Go    — product catalogue
│           ├── recommendationservice/  # Python — recommendations
│           ├── shippingservice/        # Go    — shipping cost
│           └── shoppingassistantservice/ # Python — AI assistant
│
├── platform/
│   │
│   ├── gitops/
│   │   ├── argocd/
│   │   │   ├── root-app.yaml                   # Root Application — App of Apps entrypoint
│   │   │   ├── projects/
│   │   │   │   └── platform.yaml               # AppProject: RBAC, source repos, destinations
│   │   │   └── applications/
│   │   │       ├── platform-services.yaml       # sync-wave: "1"
│   │   │       ├── security.yaml               # sync-wave: "2"
│   │   │       ├── observability.yaml          # sync-wave: "3"
│   │   │       └── online-boutique.yaml        # sync-wave: "4"
│   │   │
│   │   └── kustomize/
│   │       ├── base/                           # Shared namespaces + common labels
│   │       ├── platform-services/
│   │       │   ├── metrics-server/             # Helm chart v3.12.2
│   │       │   └── aws-load-balancer-controller/ # Helm chart v1.8.1 + IngressClass
│   │       ├── security/
│   │       │   ├── kustomization.yaml
│   │       │   ├── opa-gatekeeper/             # Helm chart v3.17.1 + 7 templates + 7 constraints
│   │       │   └── falco/                      # DaemonSet + ConfigMap + kustomization
│   │       ├── observability/
│   │       │   └── kube-prometheus-stack/      # Helm chart + dashboards + alerts + servicemonitors
│   │       ├── applications/
│   │       │   └── online-boutique/            # Base manifests for all 12 workloads
│   │       └── overlays/
│   │           ├── dev/                        # Dev: 1 replica, debug config, env=dev
│   │           └── prod/                       # Prod: HPA, higher replicas, strict limits
│   │
│   ├── infrastructure/
│   │   └── terraform/
│   │       ├── bootstrap/                      # One-time: S3 + DynamoDB + KMS
│   │       ├── environments/
│   │       │   ├── dev/                        # Dev root module
│   │       │   └── prod/                       # Prod root module
│   │       ├── modules/
│   │       │   ├── vpc/                        # VPC, subnets, IGW, NAT GW, route tables
│   │       │   ├── security-group/             # SGs for EKS, RDS, ALB
│   │       │   ├── iam/                        # EKS cluster + node group IAM roles
│   │       │   ├── eks/                        # EKS cluster, node group, OIDC, addons, EBS CSI IRSA
│   │       │   ├── ecr/                        # 11 ECR repos with lifecycle policies
│   │       │   ├── rds/                        # PostgreSQL 15.7, custom parameter group
│   │       │   ├── alb/                        # IRSA role for AWS Load Balancer Controller
│   │       │   └── argocd-bootstrap/           # ArgoCD Helm + Git secret + Root Application
│   │       └── policies/
│   │           ├── security.rego               # EKS / ECR / RDS / IAM / SG rules
│   │           ├── networking.rego             # VPC / Subnet / NAT GW / ALB rules
│   │           └── compliance.rego             # Tagging + encryption + backup rules
│   │
│   └── observability/                          # Observability runbooks
│
└── policies/                                   # Root-level OPA policies (mirrors terraform/policies/)
```

---

## 6. Infrastructure Design

### AWS Networking

```
VPC: 10.0.0.0/16   (ap-southeast-1)
DNS hostnames: enabled    DNS support: enabled
│
├── ap-southeast-1a
│     ├── Public Subnet  10.0.1.0/24   → Route: 0.0.0.0/0 → Internet Gateway
│     │     └── NAT Gateway (Elastic IP)
│     └── Private Subnet 10.0.11.0/24  → Route: 0.0.0.0/0 → NAT Gateway
│           ├── EKS Worker Nodes
│           └── RDS PostgreSQL
│
└── ap-southeast-1b
      ├── Public Subnet  10.0.2.0/24   → Route: 0.0.0.0/0 → Internet Gateway
      └── Private Subnet 10.0.12.0/24  → Route: 0.0.0.0/0 → NAT Gateway (dev: shared)
            ├── EKS Worker Nodes
            └── (RDS Multi-AZ standby — prod only)
```

**Subnet tagging** — the VPC module applies Kubernetes-specific tags required by AWS Load Balancer Controller for automatic subnet discovery:

| Tag | Value | Subnet | Purpose |
|---|---|---|---|
| `kubernetes.io/role/elb` | `1` | Public | Internet-facing ALB subnet discovery |
| `kubernetes.io/role/internal-elb` | `1` | Private | Internal ALB subnet discovery |
| `kubernetes.io/cluster/<name>` | `shared` | Both | EKS subnet ownership |

**Security Groups:**

| Security Group | Inbound | Outbound |
|---|---|---|
| EKS Control Plane | Node group (HTTPS 443) | Node group (all) |
| EKS Nodes | Control plane, node-to-node | All (ECR pull, AWS API) |
| ALB | Internet (HTTP 80, HTTPS 443) | EKS nodes |
| RDS | EKS nodes (PostgreSQL 5432) | None |

### EKS Cluster Design

```
EKS Cluster: eks-devsecops-dev-cluster
Kubernetes version: 1.33
Authentication: API_AND_CONFIG_MAP
API endpoint: public + private access enabled
Control plane logs → CloudWatch: api, audit, authenticator, controllerManager, scheduler
│
└── Managed Node Group: eks-devsecops-dev-node-group
      AMI:      AL2023_x86_64_STANDARD
      Type:     t3.medium (2 vCPU / 4 GiB)
      Capacity: ON_DEMAND
      Scaling:  desired=2, min=1, max=3
      Disk:     20 GiB gp3 (EBS)
      Update:   RollingUpdate (max_unavailable=1)
```

**EKS Addons (managed by Terraform):**

| Addon | Purpose |
|---|---|
| `vpc-cni` | Pod networking and IP allocation from VPC CIDR |
| `coredns` | Cluster DNS for service discovery |
| `kube-proxy` | Network rules on each node (iptables/ipvs) |
| `aws-ebs-csi-driver` | Dynamic PersistentVolume provisioning (gp3) — required by Prometheus |

**IAM Roles:**

| Role | Trust principal | Attached policies |
|---|---|---|
| EKS Cluster Role | `eks.amazonaws.com` | `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController` |
| EKS Node Group Role | `ec2.amazonaws.com` | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore` |
| EBS CSI Driver Role (IRSA) | OIDC → `kube-system:ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` |
| AWS LBC Role (IRSA) | OIDC → `kube-system:aws-load-balancer-controller` | Custom LBC policy (full ALB/NLB management) |

### Terraform State Management

```
Bootstrap (local state, run once):
  ├── S3 Bucket
  │     ├── Versioning: enabled
  │     ├── SSE: aws:kms (KMS key with auto-rotation)
  │     ├── Public access: fully blocked
  │     └── Lifecycle: expire non-current versions after 90 days
  ├── DynamoDB Table
  │     ├── Billing: PAY_PER_REQUEST
  │     ├── Hash key: LockID (String)
  │     ├── PITR: enabled
  │     └── SSE: enabled
  └── KMS Key
        ├── Key rotation: enabled
        └── Alias: alias/eks-devsecops-tfstate

Remote state (environments/dev/backend.tf):
  bucket         = "eks-devsecops-terraform-state-ndt"
  key            = "dev/terraform.tfstate"
  region         = "ap-southeast-1"
  dynamodb_table = "eks-devsecops-terraform-lock-ndt"
  encrypt        = true
```

### Multi-AZ High Availability

| Component | Dev | Prod |
|---|---|---|
| EKS Control Plane | Managed (always HA) | Managed (always HA) |
| EKS Nodes | 2 nodes across 2 AZs | 3+ nodes across 2+ AZs |
| NAT Gateway | 1 shared | 1 per AZ |
| RDS PostgreSQL | Single-AZ | Multi-AZ (`multi_az = true`) |
| ArgoCD | 1 replica | 2 replicas (`argocd_ha_enabled = true`) |
| ALB | Multi-AZ (managed) | Multi-AZ (managed) |

---

## 7. GitOps Workflow

### ArgoCD Architecture

```
Terraform
    └── argocd-bootstrap module
              ├── helm_release "argocd"          ArgoCD v7.6.8
              ├── kubernetes_secret (optional)   Git SSH credentials
              └── helm_release "argocd_root_app" Root Application
                          │
                          └── watches: platform/gitops/argocd/applications/
                                    │
                        ┌───────────┼───────────────────┐
                        ▼           ▼                   ▼           ▼
                 platform-     security          observability  online-boutique
                 services      (wave 2)          (wave 3)       (wave 4)
                 (wave 1)
```

**ArgoCD Configuration (Helm values set by Terraform):**

| Setting | Value | Reason |
|---|---|---|
| `server.insecure` | `true` | ALB terminates TLS externally |
| `application.resourceTrackingMethod` | `annotation` | Safer than label tracking — avoids conflicts |
| `policy.default` | `role:readonly` | Least-privilege default for UI access |
| `redis-ha.enabled` | `false` (dev) / `true` (prod) | Cost optimisation in dev |
| `dex.enabled` | `false` | SSO deferred to future enhancement |

**AppProject (`platform.yaml`):**

| Setting | Value |
|---|---|
| Permitted source repos | `https://github.com/dinhtri6905/aws-eks-devsecops-platform.git` only |
| Permitted destinations | `argocd`, `kube-system`, `monitoring`, `security`, `online-boutique` |
| Cluster resource access | All groups/kinds (required for CRDs, ClusterRoles) |
| Namespace resource access | All groups/kinds |
| RBAC roles | `admin` (platform-admins group), `readonly` (platform-viewers group) |
| Orphaned resources | Warn (non-blocking) |

### GitOps Promotion Flow

```
1. Developer pushes code change
         │
2. app-ci validates manifests, scans for secrets and CVEs
         │
3. PR reviewed and merged to main
         │
4. app-cd builds Docker image
         │
5. Trivy scans image — CRITICAL CVEs block step 6
         │
6. Image pushed to ECR with SHA tag
         │
7. `kustomize edit set image <service>=<ECR-URI>:<SHA>`
         │
8. Git commit: "chore(gitops): update image tags to <SHA>"
         │
9. ArgoCD polls Git (every 3 min) → detects diff → marks OutOfSync
         │
10. ArgoCD syncs: `kustomize build overlays/dev/` → server-side apply
         │
11. Argo Rollouts provisions green ReplicaSet → health checks pass → traffic switches to green instantly
12. Blue ReplicaSet kept for 30s (`scaleDownDelaySeconds`) for instant rollback window
         │
12. ArgoCD marks Application Synced / Healthy
```

### Environment Separation

| Environment | Overlay path | Key differences |
|---|---|---|
| `dev` | `kustomize/overlays/dev/` | 1 replica per service, `LOG_LEVEL=info`, `ENABLE_PROFILER=0`, debug-friendly config |
| `prod` | `kustomize/overlays/prod/` | Multiple replicas, strict resource limits, `LOG_LEVEL=warn`, HPA enabled |

Both overlays share the same base manifests in `kustomize/applications/online-boutique/`. Environment differences are expressed as Kustomize patches rather than duplicated YAML.

---

## 8. CI/CD Platform

### Application Pipeline

**`app-ci.yaml`** — triggered on PR to `develop` / `feature/**`:

```
gitleaks          ← secret scanning, full git history — HARD GATE
    ├── kustomize-validate   kustomize build + kubeconform (K8s 1.33 schema)
    ├── opa-k8s-policies     OPA unit tests + opa check syntax
    ├── falco-validate       Falco rule validation (native + Docker fallback)
    └── trivy-filesystem     CVE scan of source code — non-blocking, SARIF to Security tab
              │
              └── app-ci-summary  → PR comment table + Slack notification
```

**`app-cd.yaml`** — triggered on push to `main` (microservices paths):

```
detect-changes   git diff → JSON array of changed service names
    └── build-and-scan  (matrix job — one per changed service, parallel)
              ├── docker build
              ├── trivy SARIF scan    → GitHub Security tab
              ├── trivy table scan    → workflow log
              ├── trivy JSON scan     → count CRITICAL CVEs
              │     └── BLOCK push if CRITICAL count > 0
              └── docker push  <ECR>/<service>:<SHA> + :latest
                        │
                        └── update-gitops
                                  ├── kustomize edit set image (per service)
                                  ├── git commit "chore(gitops): update to <SHA>"
                                  ├── git push to main
                                  └── Slack notification
```

### Infrastructure Pipeline

**`terraform-ci.yaml`** — triggered on PR to `develop` / `feature/**` (terraform paths):

```
fmt-validate    terraform fmt -check + terraform validate
tflint          AWS provider best practices, deprecated args
tfsec           Static security misconfigurations (SARIF → Security tab)
checkov         CIS Benchmark, NIST, SOC 2 compliance mappings (SARIF)
    └── ci-summary  → PR comment + Slack notification
```

**`terraform-cd.yaml`** — triggered on push to `main` or manual dispatch:

```
plan       terraform init + terraform plan -out tfplan
           terraform show -json tfplan → artifact
    │
opa-gate   opa eval security.rego    → deny violations block apply
           opa eval networking.rego  → deny violations block apply
           opa eval compliance.rego  → deny violations block apply
           warn violations → logged, non-blocking
    │
apply      terraform apply (saved plan)
           only if: OPA passes AND (push to main with changes OR manual apply)
    │
destroy    manual dispatch only — isolated environment with required reviewers
```

**`check-scan.yaml`** — scheduled nightly:

```
opa-full-scan    all 3 policies against latest plan JSON
tfsec-deep       extended ruleset (rules suppressed in CI for noise reduction)
    └── scan-summary  → SARIF upload + Slack
```

### Security Gates

| Gate | Tool | Blocks |
|---|---|---|
| Secret scanning | Gitleaks | All downstream CI jobs |
| Filesystem CVE | Trivy fs | Logged only (non-blocking) |
| IaC security | tfsec | PR fails — merge blocked |
| IaC compliance | Checkov | PR fails — merge blocked |
| Terraform policy | OPA Rego | `terraform apply` |
| Image CRITICAL CVEs | Trivy image | ECR push |
| Admission control | OPA Gatekeeper | Pod creation on cluster |

### Deployment Strategy

**Online Boutique** uses **Blue/Green deployment** via Argo Rollouts. Each service's `Deployment` is replaced with a `Rollout` resource:

```yaml
# platform/gitops/kustomize/applications/online-boutique/frontend/rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: <ECR>/frontend:<SHA>
  strategy:
    blueGreen:
      activeService: frontend-active      # production traffic
      previewService: frontend-preview    # health-check only, no traffic
      autoPromotionEnabled: true
      autoPromotionSeconds: 60            # wait 60s after green is Ready → promote
      scaleDownDelaySeconds: 30           # keep blue alive 30s post-promotion → instant rollback
```

Two Services are required per service: `<name>-active` (production) and `<name>-preview` (green, no traffic). After `autoPromotionSeconds`, Argo Rollouts patches the active Service selector — traffic switches to green atomically. Rollback: `kubectl argo rollouts undo <name> -n online-boutique`.

See [ADR-008](#adr-008-bluegreen-deployment-strategy-via-argo-rollouts) for the full decision rationale.

      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: <ECR>/frontend:<SHA>
  strategy:
    blueGreen:
      activeService: frontend-active      # production traffic
      previewService: frontend-preview    # health-check only (no traffic)
      autoPromotionEnabled: true
      autoPromotionSeconds: 60            # wait 60s after green is Ready → promote
      scaleDownDelaySeconds: 30           # keep blue alive 30s post-promotion → instant rollback window


Two Services are required per service: `<name>-active` (production) and `<name>-preview` (green stack, no traffic). After `autoPromotionSeconds`, Argo Rollouts patches the active Service selector — all traffic switches to green in a single atomic operation. Rollback: `kubectl argo rollouts undo <name> -n online-boutique`.

See [ADR-008](#adr-008-bluegreen-deployment-strategy-via-argo-rollouts) for the full decision rationale.

---

## 9. GitHub Secrets & Environments

### Repository Secrets

Navigate to: **Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required by | How to obtain |
|---|---|---|
| `AWS_DEV_ROLE_ARN` | `terraform-cd`, `app-cd`, `check-scan` | ARN of IAM Role with GitHub OIDC trust. See [OIDC Authentication](#oidc-authentication). |
| `BUCKET_TF_STATE` | `terraform-cd`, `check-scan` | S3 bucket name from Phase 0 bootstrap output. Bucket name only — not ARN. |
| `TF_VAR_DB_PASSWORD` | `terraform-cd` | RDS master password. Min 8 chars. Must not contain `@`, `/`, `"`. |
| `GITOPS_REPO_URL` | `terraform-cd` | `https://github.com/<org>/aws-eks-devsecops-platform` — used by ArgoCD bootstrap to configure the repo connection. |
| `GITOPS_BOT_TOKEN` | `app-cd` | GitHub PAT with `Contents: read/write` on this repository. Used by `update-gitops` job to commit image tag changes to `main`. Create at **Settings → Developer settings → Fine-grained personal access tokens**. |
| `AWS_ACCOUNT_ID` | `app-cd` | 12-digit AWS account ID. `aws sts get-caller-identity --query Account --output text` |
| `SLACK_WEBHOOK_URL` | all workflows | Incoming Webhook URL. Create at **api.slack.com/apps → Incoming Webhooks → Add New Webhook to Workspace**. |

### OIDC Authentication

All workflows authenticate to AWS via OpenID Connect — no long-lived access keys stored in GitHub secrets.

**IAM Role trust policy for `AWS_DEV_ROLE_ARN`:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<your-org>/aws-eks-devsecops-platform:*"
      }
    }
  }]
}
```

For production, tighten `sub` to the specific environment to restrict to the apply job only:

```json
"token.actions.githubusercontent.com:sub": "repo:<your-org>/aws-eks-devsecops-platform:environment:dev-apply"
```

**Required IAM permissions on the role:**

| Service | Minimum permissions |
|---|---|
| EKS | `eks:*` |
| EC2 / VPC | `ec2:*` |
| IAM | Create/update/delete roles, policies, OIDC providers |
| ECR | `ecr:GetAuthorizationToken`, `ecr:*` on target repositories |
| S3 | Read/write on the state bucket |
| DynamoDB | Read/write on the lock table |
| KMS | `kms:Decrypt`, `kms:GenerateDataKey` on the state key |
| RDS | `rds:*` |
| CloudWatch Logs | `logs:*` |

### Environment Protection Rules

Navigate to: **Repository → Settings → Environments → New environment**

| Environment | Used by | Protection rules |
|---|---|---|
| `dev-plan` | `terraform-cd` → `plan` | None — runs automatically on every trigger |
| `dev-apply` | `terraform-cd` → `apply` | Optional: 1+ required reviewers for controlled applies |
| `dev-destroy` | `terraform-cd` → `destroy` | **Mandatory: 2+ required reviewers.** Branch restricted to `main` only. |

> The `dev-destroy` environment must always be protected. An unprotected destroy with manual dispatch enabled can result in complete infrastructure loss in under 15 minutes.

---

## 10. Security Architecture

Security is implemented at seven distinct layers, following a defense-in-depth approach.

### IAM & Least Privilege

- **No long-lived access keys** — GitHub Actions uses OIDC; EC2 nodes use instance profiles; platform controllers use IRSA
- **EKS node role** — `AmazonEC2ContainerRegistryReadOnly` only; no write access to ECR from nodes
- **IRSA scoping** — EBS CSI Driver role trust is scoped to `system:serviceaccount:kube-system:ebs-csi-controller-sa`; LBC role trust scoped to `system:serviceaccount:kube-system:aws-load-balancer-controller`
- **ArgoCD RBAC** — default role is `readonly`; admin access requires membership in `platform-admins` group
- **IAM policy gate** — OPA Rego blocks any Terraform plan that grants `Action: * / Resource: *`

### Secrets Management

- **RDS password** — injected via `TF_VAR_db_password` environment variable at apply time; never stored in code or state in plaintext (`sensitive = true`)
- **Git credentials** — optional SSH private key for private repos injected via `TF_VAR_gitops_repo_ssh_private_key`; stored in Kubernetes Secret with ArgoCD repository label
- **Terraform state** — encrypted at rest with KMS customer-managed key (`enable_key_rotation = true`); versioning enabled for recovery
- **No hardcoded credentials** — Gitleaks scans full git history on every PR

### Image Scanning

Three-stage image scanning pipeline in `app-cd.yaml`:

```
Stage 1: SARIF scan     → uploaded to GitHub Security tab (always, regardless of outcome)
Stage 2: Table scan     → printed to workflow log in human-readable format
Stage 3: JSON scan      → CRITICAL CVE count extracted
         └── count > 0  → ECR push BLOCKED, CVE list printed, workflow exits 1
         └── count == 0 → ECR push proceeds
```

Additionally, ECR has `scan_on_push = true` — every image is rescanned by AWS Inspector on arrival, independent of the GitHub Actions scan.

### Container Security

OPA Gatekeeper enforces 7 policies on every Pod admitted to the cluster:

| Constraint | ConstraintTemplate CRD | Scope | Effect if violated |
|---|---|---|---|
| `allow-ecr-and-trusted-registries-only` | `K8sAllowedRepos` | `online-boutique` namespace | Pod rejected — image from unknown registry |
| `disallow-latest-tag` | `K8sDisallowedTags` | All namespaces | Pod rejected — must use explicit image tag |
| `disallow-privileged` | `K8sDisallowPrivileged` | All namespaces | Pod rejected — `privileged: true` forbidden |
| `require-labels` | `K8sRequiredLabels` | `online-boutique` namespace | Pod rejected — `app.kubernetes.io/name` and `app.kubernetes.io/part-of` required |
| `require-non-root` | `K8sNonRoot` | All namespaces | Pod rejected — must run as non-root UID |
| `require-read-only-root-filesystem` | `K8sReadOnlyRootFs` | All namespaces | Pod rejected — `readOnlyRootFilesystem: true` required |
| `require-resource-limits` | `K8sRequiredResources` | All namespaces | Pod rejected — CPU and memory limits required |

System namespaces (`kube-system`, `gatekeeper-system`, `falco`, `monitoring`, `argocd`) are excluded from enforcement to prevent bootstrapping deadlocks.

The Gatekeeper `ValidatingWebhookConfiguration` `caBundle` is mutated at runtime and ignored by ArgoCD (`ignoreDifferences`) to prevent sync loops.

### Network Security

| Boundary | Control |
|---|---|
| Internet → cluster | AWS ALB (public subnets only); EKS nodes have no public IPs |
| ALB → pods | Target Group on EKS node ports; Security Group restricts to ALB SG only |
| Pod → RDS | RDS Security Group allows port 5432 from EKS node SG only |
| Pod → ECR/AWS APIs | NAT Gateway egress via private subnets; no direct internet exposure |
| Sensitive ports (22, 3389, 3306, 5432, 6379) | OPA Rego denies any Security Group rule opening these to `0.0.0.0/0` |

### Admission Control

Gatekeeper runs as two replicas in `gatekeeper-system` with `failurePolicy: Ignore` in dev (to prevent cluster lockout if Gatekeeper is unavailable) and `failurePolicy: Fail` in prod (strict enforcement).

The admission flow for every `kubectl apply` (including ArgoCD sync):

```
Client request
      │
      ▼
Kubernetes API server
      │
      ▼ (ValidatingAdmissionWebhook)
OPA Gatekeeper
      │
      ├── ALLOW: all constraints pass → resource created
      └── DENY:  any constraint violated → request rejected with detailed message
```

### Supply Chain Security

| Control | Implementation |
|---|---|
| Known-good base images | Trivy CI scan + Trivy ECR scan enforce no CRITICAL CVEs |
| Immutable image references | `disallow-latest-tag` Gatekeeper constraint + Kustomize SHA tag pinning |
| Trusted registries only | `allow-ecr-and-trusted-registries-only` Gatekeeper constraint |
| Secret detection | Gitleaks scans full git history on every PR — hard gate |
| IaC integrity | OPA Rego gates on Terraform plan prevent policy-violating infrastructure |

---

## 11. Observability Architecture

### Metrics Collection

Prometheus (via kube-prometheus-stack) scrapes the following targets:

| Target | Metrics provided |
|---|---|
| `node-exporter` (DaemonSet) | Per-node CPU, memory, disk I/O, network I/O, filesystem usage |
| `kube-state-metrics` | Kubernetes object state: pod phase, deployment replicas, PVC status, HPA status |
| ArgoCD | Application sync status, health grade, resource counts, repository sync duration |
| OPA Gatekeeper | Constraint violation counts, admission webhook latency, audit results |
| Falco | Alert count by rule name and priority |
| Online Boutique services | gRPC request rates, error rates, latency (from `/metrics` endpoints per service) |
| Prometheus self | Scrape durations, rule evaluation latency, TSDB metrics |

### Logging Pipeline

- **EKS control plane logs** — shipped to CloudWatch Log Group `/aws/eks/eks-devsecops-dev-cluster/cluster` with 7-day retention. Log types: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`
- **Application logs** — written to stdout/stderr by all Online Boutique services; collected by the node's container runtime and accessible via `kubectl logs`
- **RDS logs** — connection logs, DDL statements, and slow queries (>1000ms) via custom parameter group (`log_connections`, `log_disconnections`, `log_statement = ddl`, `log_min_duration_statement = 1000`)
- **Falco alerts** — written to stdout and optionally forwarded to external sinks (Slack, Elasticsearch) via Falcosidekick

### Dashboards

Three custom Grafana dashboards are provisioned via ConfigMaps:

| Dashboard | Key panels |
|---|---|
| `cluster-overview.json` | Node ready status, pod count by namespace, cluster CPU/memory utilisation, ArgoCD app health summary |
| `node-metrics.json` | Per-node CPU usage, memory usage, disk read/write throughput, network in/out — time-series |
| `application-metrics.json` | Online Boutique request rate (RPS), error rate (%), latency P50/P95/P99 — RED method |

### Alerting

Three PrometheusRule resources define alert conditions:

| Alert | Condition | Severity | Notification |
|---|---|---|---|
| `HighCpuUsage` | Node CPU > 80% for 5 consecutive minutes | `warning` | Alertmanager → Slack |
| `HighMemoryUsage` | Node memory usage > 85% for 5 consecutive minutes | `warning` | Alertmanager → Slack |
| `PodRestartLoop` | Pod restart count increases > 5 times within 15 minutes | `critical` | Alertmanager → Slack |

### Service Discovery

Two ServiceMonitor resources configure automatic Prometheus target discovery:

- **`kubernetes.yaml`** — covers kube-apiserver, kubelet (cAdvisor + node metrics), kube-state-metrics, node-exporter, and CoreDNS
- **`online-boutique.yaml`** — selects all pods in the `online-boutique` namespace with label `app.kubernetes.io/part-of: aws-eks-devsecops-platform` and scrapes `/metrics` on the metrics port

---

## 12. Online Boutique Microservices

### Service Overview

| Service | Language | Protocol | Port | Role |
|---|---|---|---|---|
| `frontend` | Go | HTTP (external), gRPC (internal) | 8080 | Web UI, entry point, aggregates all backend services |
| `cartservice` | C# (.NET) | gRPC | 7070 | Shopping cart state; backed by Redis (`redis-cart`) |
| `productcatalogservice` | Go | gRPC | 3550 | Product catalogue served from `products.json` |
| `currencyservice` | Node.js | gRPC | 7000 | Real-time currency conversion (170+ currencies) |
| `paymentservice` | Node.js | gRPC | 50051 | Mock payment processing (always succeeds) |
| `shippingservice` | Go | gRPC | 50051 | Shipping cost estimation |
| `emailservice` | Python | gRPC | 8080 | Order confirmation email simulation (no actual email sent) |
| `checkoutservice` | Go | gRPC | 5050 | Order orchestration — coordinates cart, payment, shipping, email |
| `recommendationservice` | Python | gRPC | 8080 | Product recommendations based on current cart |
| `adservice` | Java | gRPC | 9555 | Contextual advertisement service |
| `loadgenerator` | Python (Locust) | HTTP | — | Simulates realistic user traffic for demo/testing |
| `redis-cart` | Redis | TCP | 6379 | In-memory cart storage for `cartservice` |
| `shoppingassistantservice` | Python | HTTP | 8080 | AI-powered shopping assistant |

### Service Communication Flow

```
Browser (HTTP)
    │
    ▼
AWS ALB (Internet-facing)
    │
    ▼
frontend :8080
    │
    ├──gRPC──► productcatalogservice :3550
    │               └── returns product list / detail
    │
    ├──gRPC──► currencyservice :7000
    │               └── converts prices
    │
    ├──gRPC──► cartservice :7070
    │               └──TCP──► redis-cart :6379
    │
    ├──gRPC──► recommendationservice :8080
    │               └──gRPC──► productcatalogservice
    │
    ├──gRPC──► adservice :9555
    │
    └──gRPC──► checkoutservice :5050
                    ├──gRPC──► cartservice
                    ├──gRPC──► productcatalogservice
                    ├──gRPC──► currencyservice
                    ├──gRPC──► shippingservice :50051
                    ├──gRPC──► paymentservice :50051
                    └──gRPC──► emailservice :8080
```

All inter-service communication uses gRPC over the Kubernetes cluster DNS (`<service>.<namespace>.svc.cluster.local`). The frontend is the only service with an external-facing endpoint via the ALB Ingress.

---

## 13. Deployment Guide

### Phase 0 — Bootstrap Remote State

Run once to create the Terraform backend. This apply runs against local state — no backend is needed for the bootstrap itself.

```bash
cd platform/infrastructure/terraform/bootstrap

# Review what will be created
terraform init
terraform plan

# Create S3 bucket, DynamoDB table, KMS key
terraform apply
```

Note the outputs — you will need the bucket name and table name for `backend.tf`.

Configure `environments/dev/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "<bootstrap-output: bucket name>"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "<bootstrap-output: table name>"
    encrypt        = true
  }
}
```

### Phase 1 — Infrastructure Provisioning

**Option A: Automated via GitHub Actions (recommended)**

Push any change to `platform/infrastructure/terraform/environments/dev/` on `main`, or trigger `terraform-cd.yaml` manually with `action: apply`. The pipeline runs plan → OPA gate → apply.

**Option B: Manual (initial setup or debugging)**

```bash
cd platform/infrastructure/terraform/environments/dev

export TF_VAR_db_password="<your-secure-password>"
export TF_VAR_gitops_repo_url="https://github.com/<org>/aws-eks-devsecops-platform"

terraform init
terraform plan
terraform apply
```

After apply, update local kubeconfig:

```bash
$(terraform output -raw kubeconfig_command)
# equivalent to:
# aws eks update-kubeconfig --region ap-southeast-1 --name eks-devsecops-dev-cluster

kubectl get nodes   # expect 2 nodes in Ready state
kubectl get pods -n argocd  # expect ArgoCD pods Running
```

### Phase 2 — Platform Components

ArgoCD takes over automatically after Terraform creates the Root Application. Monitor sync progress:

```bash
# Port-forward ArgoCD UI (no ingress required)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Open `https://localhost:8080`. All four Applications (`platform-services`, `security`, `observability`, `online-boutique`) should appear and transition to `Synced / Healthy` within 5–10 minutes.

Verify platform services:

```bash
# Metrics Server
kubectl top nodes
kubectl top pods -A

# AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# OPA Gatekeeper
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates

# Falco
kubectl get pods -n falco

# Prometheus + Grafana
kubectl get pods -n monitoring
```

### Phase 3 — GitOps Setup

The App of Apps pattern is wired by Terraform. No manual steps are required. Verify:

```bash
# Check Root Application
kubectl get application -n argocd eks-devsecops-dev-root

# Check all child Applications
kubectl get applications -n argocd

# Verify ArgoCD is watching the correct repo path
kubectl get application eks-devsecops-dev-root -n argocd \
  -o jsonpath='{.spec.source.path}'
```

**Important:** The Terraform variable `gitops_root_app_path` must be set to `platform/gitops/argocd/applications` (the actual folder). The default value `platform/gitops/argocd/apps` is incorrect. Set this in `terraform.tfvars` before apply.

### Phase 4 — Infrastructure CI Pipeline

Push a change to any Terraform file on a `feature/**` branch:

```bash
git checkout -b feature/update-node-type
# Edit environments/dev/variables.tf
git add . && git commit -m "feat: change node instance type"
git push origin feature/update-node-type
```

Open a PR to `develop`. The `terraform-ci.yaml` workflow runs automatically — check the PR status checks and the PR comment with results.

### Phase 5 — Application CI/CD Pipeline

**CI (on PR):**

```bash
git checkout -b feature/update-frontend
# Edit microservices-application/online-boutique/src/frontend/main.go
git add . && git commit -m "feat: update frontend handler"
git push origin feature/update-frontend
# Open PR → app-ci runs automatically
```

**CD (on merge to main):**

After the PR is merged, `app-cd.yaml` triggers automatically. It detects `frontend` as a changed service, builds and scans the image, pushes to ECR, and commits an updated `kustomization.yaml`. ArgoCD detects the commit and syncs the change to the cluster within minutes.

### Phase 6 — Application Deployment

Verify the Online Boutique is running:

```bash
kubectl get pods -n online-boutique
kubectl get ingress -n online-boutique

# Get the ALB DNS name
kubectl get ingress -n online-boutique frontend \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open the ALB DNS name in a browser — the Online Boutique storefront should load.

The `loadgenerator` pod runs automatically and simulates user traffic, generating metrics visible in Grafana.

### Phase 7 — Security & Observability

**Verify Gatekeeper policies are enforced:**

```bash
# List all active constraints
kubectl get constraints

# Test a policy violation (expect rejection)
kubectl run test --image=nginx:latest -n online-boutique
# Expected: admission webhook denied (latest tag, missing labels, no resource limits)
```

**Access Grafana:**

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Default credentials: admin / prom-operator (check Helm values for override)
```

Open `http://localhost:3000` → Dashboards → Browse → select a dashboard.

**View Falco alerts:**

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50
```

---

## 14. Validation & Testing

### Infrastructure Validation

```bash
# Terraform format check
terraform fmt -check -recursive platform/infrastructure/terraform/

# Terraform validation
cd platform/infrastructure/terraform/environments/dev
terraform validate

# OPA policy evaluation against a plan
terraform plan -out=tfplan
terraform show -json tfplan > /tmp/plan.json

for policy in security networking compliance; do
  echo "=== $policy.rego ==="
  opa eval \
    --format pretty \
    --data "platform/infrastructure/terraform/policies/${policy}.rego" \
    --input /tmp/plan.json \
    "data.terraform.${policy}.deny"
done

# tfsec
tfsec platform/infrastructure/terraform/

# Checkov
checkov -d platform/infrastructure/terraform/ --framework terraform
```

### Security Validation

```bash
# Gitleaks — scan full history
gitleaks detect --source . --verbose

# Trivy — filesystem scan
trivy fs . --severity CRITICAL,HIGH

# Trivy — image scan (after building)
docker build -t test-image:latest microservices-application/online-boutique/src/frontend/
trivy image test-image:latest --severity CRITICAL

# OPA Gatekeeper — verify policy enforcement
# Attempt to create a pod with a policy violation:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: violation-test
  namespace: online-boutique
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      privileged: true
EOF
# Expected output: admission webhook denied (multiple violations)

# Falco — verify rules are loaded
kubectl exec -n falco $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- falco --list | grep -i shell
```

### GitOps Validation

```bash
# Kustomize build validation
kustomize build platform/gitops/kustomize/overlays/dev/ > /dev/null && echo "OK"
kustomize build platform/gitops/kustomize/security/ > /dev/null && echo "OK"
kustomize build platform/gitops/kustomize/observability/kube-prometheus-stack/ > /dev/null && echo "OK"

# kubeconform schema validation
kustomize build platform/gitops/kustomize/overlays/dev/ | \
  kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.33.0

# ArgoCD application health
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'

# Verify selfHeal is working (make a manual change and observe it reverting)
kubectl scale deployment frontend -n online-boutique --replicas=5
sleep 180
kubectl get deployment frontend -n online-boutique -o jsonpath='{.spec.replicas}'
# Expected: 1 (reverted by ArgoCD selfHeal)
```

### Application Validation

```bash
# All Online Boutique pods running
kubectl get pods -n online-boutique

# Check Argo Rollouts status for all services
kubectl argo rollouts list rollouts -n online-boutique

# Watch a rollout in progress
kubectl argo rollouts get rollout frontend -n online-boutique --watch

# Endpoint reachability
ALB=$(kubectl get ingress -n online-boutique frontend \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -o /dev/null -w "%{http_code}" "http://${ALB}"
# Expected: 200

# gRPC service health (example: productcatalogservice)
kubectl exec -n online-boutique deploy/frontend -- \
  grpc_health_probe -addr=productcatalogservice:3550
# Expected: SERVING

# Prometheus scraping Online Boutique metrics
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.labels.namespace=="online-boutique") | {job: .labels.job, health: .health}'
```

---

## 15. Disaster Recovery Strategy

### Terraform State Recovery

The S3 backend has versioning enabled. If the state file is corrupted or accidentally deleted:

```bash
# List state file versions
aws s3api list-object-versions \
  --bucket eks-devsecops-terraform-state-ndt \
  --prefix dev/terraform.tfstate

# Restore a previous version
aws s3api get-object \
  --bucket eks-devsecops-terraform-state-ndt \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup
```

DynamoDB Point-in-Time Recovery (PITR) is enabled on the lock table — AWS can restore it to any second within the last 35 days.

### EKS Cluster Recovery

EKS managed control plane is AWS-managed and highly available. In the event of a full cluster loss:

1. Run `terraform apply` — Terraform recreates the cluster from IaC definition
2. ArgoCD bootstraps automatically (Terraform module installs it and creates the Root App)
3. ArgoCD syncs all Applications from Git — cluster state is fully restored from Git within minutes

The recovery time objective (RTO) is approximately the time for `terraform apply` to complete (~15 minutes) plus ArgoCD sync time (~5 minutes).

### RDS Recovery

- Automated backups retained for 7 days with a daily backup window (03:00–04:00 UTC)
- Point-in-time restore to any second within the retention period:

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier eks-devsecops-dev-postgres \
  --target-db-instance-identifier eks-devsecops-dev-postgres-restored \
  --restore-time "2025-01-15T10:00:00Z" \
  --region ap-southeast-1
```

For production, enable `deletion_protection = true` and `skip_final_snapshot = false` to ensure a final snapshot is taken before any instance deletion.

### Application Rollback

**Instant rollback (Blue/Green — recommended):**

The blue ReplicaSet remains running for `scaleDownDelaySeconds` (30s) after promotion. During this window, rollback is instantaneous:

```bash
# Undo a rollout — traffic returns to blue immediately
kubectl argo rollouts undo frontend -n online-boutique

# Check rollout status
kubectl argo rollouts status frontend -n online-boutique

# View rollout history
kubectl argo rollouts history frontend -n online-boutique
```

**Git-based rollback (after blue has been scaled down):**

```bash
# Find the previous good commit
git log --oneline platform/gitops/kustomize/overlays/dev/kustomization.yaml

# Revert to previous image tag
git revert <bad-commit-sha>
git push origin main
# ArgoCD detects the revert commit and syncs → Argo Rollouts runs a new blue/green cycle
```

**ArgoCD UI rollback:**
Application → History → select a previous sync → Rollback. This creates a new Rollout with the previous image, going through the full blue/green cycle.

---

## 16. Troubleshooting

### `gitops_root_app_path` mismatch

**Symptom:** ArgoCD Root Application shows `ComparisonError` — path not found in repository.

**Cause:** The Terraform variable `gitops_root_app_path` defaults to `platform/gitops/argocd/apps` but the actual folder is `platform/gitops/argocd/applications`.

**Fix:** Set the correct value in `terraform.tfvars` or as a variable override:

```hcl
gitops_root_app_path = "platform/gitops/argocd/applications"
```

### ArgoCD project name mismatch

**Symptom:** Child Applications show `InvalidSpecError: application references project platform which does not exist`.

**Cause:** The Terraform variable `argocd_project_name` defaults to `platform-project` but all Application manifests reference `project: platform`.

**Fix:** Either update the Terraform variable:

```hcl
argocd_project_name = "platform"
```

Or update all Application YAMLs to match the Terraform default (`project: platform-project`). The former is preferred — it requires changing one variable rather than four YAML files.

### Gatekeeper blocks ArgoCD sync

**Symptom:** ArgoCD Application shows `SyncFailed` with a message from the Gatekeeper admission webhook.

**Cause:** A manifest being synced violates one of the 7 Gatekeeper constraints (missing labels, no resource limits, privileged container, etc.).

**Fix:** Check the constraint's `excludedNamespaces`. System namespaces must be excluded. For application namespaces, fix the manifest to comply with the constraint:

```bash
# View constraint violations
kubectl get constraint -o json | \
  jq '.items[] | {name: .metadata.name, violations: .status.violations}'
```

### Pods stuck in `Pending` — insufficient capacity

**Symptom:** `kubectl describe pod <name>` shows `0/2 nodes are available: Insufficient cpu`.

**Cause:** The full platform stack (ArgoCD + Gatekeeper + Falco + Prometheus + Grafana + 11 services) can exceed 2 × t3.medium nodes.

**Fix:**

```bash
terraform apply -var="node_desired_size=3"
```

### `kubectl get nodes` returns empty output after apply

```bash
# Re-generate kubeconfig
aws eks update-kubeconfig \
  --name eks-devsecops-dev-cluster \
  --region ap-southeast-1

# Verify node group status
aws eks describe-nodegroup \
  --cluster-name eks-devsecops-dev-cluster \
  --nodegroup-name eks-devsecops-dev-node-group \
  --region ap-southeast-1 \
  --query 'nodegroup.{status: status, health: health}'
```

### RDS password rejected at apply time

`TF_VAR_db_password` is a shell environment variable — it must be re-exported in each new session:

```bash
export TF_VAR_db_password="<your-password>"
terraform apply
```

### Trivy blocks ECR push — CRITICAL CVEs

A service has unfixed CRITICAL CVEs in its base image. Options in order of preference:

1. **Update base image** — bump to a patched version in `Dockerfile`
2. **Pin patched digest** — `FROM golang:1.23.4@sha256:<digest>` for reproducibility
3. **Add `.trivyignore`** — document accepted risk with CVE ID, justification, and expiry date

### ArgoCD shows `OutOfSync` on Gatekeeper after install

**Cause:** Gatekeeper injects its own `caBundle` into `ValidatingWebhookConfiguration` at runtime. ArgoCD detects this as a drift.

**Fix:** The `ignoreDifferences` block in `security.yaml` handles this. Verify it covers all webhook indices:

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle
      - /webhooks/1/clientConfig/caBundle
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle
```

---

## 17. Future Enhancements

### Short-Term

| Enhancement | Rationale |
|---|---|
| **ArgoCD webhook** | Replace 3-minute polling with instant Git push notification — reduces deployment latency |
| **Argo Rollouts Canary** | Extend Argo Rollouts to support canary strategy with Analysis templates for automated promotion/abort based on Prometheus metrics |
| **External Secrets Operator** | Sync secrets from AWS Secrets Manager to Kubernetes Secrets — eliminates in-cluster secret management |
| **Cluster Autoscaler** | Automatic node scaling based on unschedulable pod count — currently node group has `lifecycle.ignore_changes` on `desired_size` |
| **HTTPS/TLS termination** | ACM certificate on ALB listener — currently HTTP only |

### Medium-Term

| Enhancement | Rationale |
|---|---|
| **GitHub SSO for ArgoCD** | Replace initial admin password with GitHub OAuth via Dex — `dex.enabled = false` today |
| **Falcosidekick** | Route Falco alerts to Slack and Prometheus — currently alerts are only in pod logs |
| **Distributed tracing** | Add AWS X-Ray or Jaeger to Online Boutique for request tracing across gRPC services |
| **OPA Gatekeeper mutation** | Add `MutatingWebhookConfiguration` to auto-inject resource limits rather than reject pods |
| **Multi-region DR** | Deploy a standby cluster in `ap-northeast-1` with RDS cross-region replication |

### Long-Term

| Enhancement | Rationale |
|---|---|
| **Multi-cluster ArgoCD** | Manage dev + prod clusters from a single ArgoCD instance |
| **ApplicationSet** | Replace manual Application YAMLs with ApplicationSet generators for environment and service matrix |
| **Vault integration** | Replace AWS Secrets Manager with HashiCorp Vault for dynamic secrets and PKI |
| **Service mesh (Istio)** | mTLS between all Online Boutique services, traffic management, circuit breaking |
| **Cost optimisation** | Karpenter for node provisioning (ARM/Spot instances), KEDA for event-driven scaling |

---

## 18. References

### Official Documentation

- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Falco Documentation](https://falco.org/docs/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

### Key Helm Chart Versions Used

| Chart | Version | Repository |
|---|---|---|
| `argo-cd` | 7.6.8 | `https://argoproj.github.io/argo-helm` |
| `argocd-apps` | 2.0.2 | `https://argoproj.github.io/argo-helm` |
| `gatekeeper` | 3.17.1 | `https://open-policy-agent.github.io/gatekeeper/charts` |
| `metrics-server` | 3.12.2 | `https://kubernetes-sigs.github.io/metrics-server/` |
| `aws-load-balancer-controller` | 1.8.1 | `https://aws.github.io/eks-charts` |

### Project Inspiration

- [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) — Demo microservices application
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/) — Security, networking, and reliability guidance
- [GitOps with ArgoCD](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/) — App of Apps pattern and GitOps principles
