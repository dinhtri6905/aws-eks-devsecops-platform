Cloud-Native Secure GitOps Platform on AWS EKS
```bash
Terraform (Infrastructure Provisioning)
│
├── VPC
├── Security Groups
├── IAM + IRSA
├── EKS
├── ECR
├── RDS PostgreSQL
├── ALB Infrastructure
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
└── Online Boutique (Microservices Demo)
├── Frontend
├── Product Catalog
├── Cart Service
├── Checkout Service
├── Payment Service
└── Other Microservices
```

```bash
Developer
│
▼
Pull Request
│
├── Gitleaks (Secret Scanning)
├── Terraform Validate & Format Check
├── tfsec + Checkov (IaC Security)
├── OPA Policy Testing
├── Falco Rules Validation
└── Terraform Plan
│
▼
Code Review & Approval
│
▼
Merge to Main
│
▼
Terraform Apply
│
├── AWS Infrastructure
└── ArgoCD Bootstrap
│
▼
Build Docker Images
│
▼
Trivy Image Scanning
│
▼
Push Images to Amazon ECR
│
▼
Update GitOps Manifests
│
▼
Commit New Image Tag
│
▼
ArgoCD Detects Changes
│
▼
Automatic Synchronization
│
▼
Deploy to Amazon EKS
│
├── OPA Gatekeeper Enforcement
├── Falco Runtime Monitoring
├── Prometheus Metrics Collection
└── Grafana Dashboards
```