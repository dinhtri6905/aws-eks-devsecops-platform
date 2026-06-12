```bash
PHASE 0 - BOOTSTRAP

Local Machine
│
▼
Terraform Bootstrap
│
├── S3 Remote State
├── DynamoDB State Locking
└── KMS Encryption
│
▼
Terraform Backend Ready

──────────────────────────────────────────────

PHASE 1 - INFRASTRUCTURE AS CODE

Terraform Modules
│
├── VPC
├── Security Groups
├── IAM
├── EKS
├── ECR
├── ALB
└── RDS
│
▼
environments/dev
│
▼
Terraform Apply
│
▼
AWS Infrastructure Ready

Result:

* VPC
* Public Subnets
* Private Subnets
* NAT Gateway
* Security Groups
* IAM Roles
* Amazon EKS
* Amazon ECR
* Amazon RDS
* ALB-ready Environment

──────────────────────────────────────────────

PHASE 2 - PLATFORM COMPONENTS

EKS Cluster
│
├── ArgoCD
├── AWS Load Balancer Controller
├── Metrics Server
├── OPA Gatekeeper
├── Falco
├── Prometheus
└── Grafana
│
▼
Platform Services Ready

──────────────────────────────────────────────

PHASE 3 - GITOPS SETUP

Git Repository
│
└── platform/gitops/
│
├── argocd/
└── kustomize/
├── base/
└── overlays/dev/
│
▼
ArgoCD Applications
│
▼
ArgoCD Connected To Git Repository

──────────────────────────────────────────────

PHASE 4 - CI PIPELINE

Pull Request
│
├── Gitleaks
├── Terraform Validation
├── tfsec
├── Checkov
├── OPA Policy Testing
├── Falco Rules Validation
└── Terraform Plan
│
▼
Code Review
│
▼
Merge

──────────────────────────────────────────────

PHASE 5 - CD PIPELINE

Merge To Main
│
▼
Terraform Apply
│
▼
Build Docker Image
│
▼
Trivy Image Scan
│
▼
Push Image To Amazon ECR
│
▼
Update Kustomize Image Tag
│
▼
Commit To GitOps Repository

──────────────────────────────────────────────

PHASE 6 - GITOPS DEPLOYMENT

GitOps Repository Updated
│
▼
ArgoCD Detects Changes
│
▼
ArgoCD Sync
│
▼
Deploy New Version To EKS

──────────────────────────────────────────────

PHASE 7 - SECURITY & OBSERVABILITY

Running Workloads
│
├── OPA Gatekeeper
│      └── Policy Enforcement
│
├── Falco
│      └── Runtime Threat Detection
│
├── Prometheus
│      └── Metrics Collection
│
└── Grafana
└── Dashboards & Visualization

──────────────────────────────────────────────

FINAL ARCHITECTURE

Developer
│
▼
GitHub Repository
│
├── Terraform
├── GitHub Actions
└── GitOps Manifests
│
▼
AWS Infrastructure
│
├── VPC
├── EKS
├── ECR
├── ALB
└── RDS
│
▼
ArgoCD
│
▼
Amazon EKS
│
├── Online Boutique
├── OPA Gatekeeper
├── Falco
├── Prometheus
└── Grafana
```