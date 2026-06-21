# Platform Overview

## What This Platform Is

The Cloud-Native Secure GitOps Platform is a production-inspired reference
architecture that demonstrates how to build, secure, deploy, and operate
cloud-native applications on Amazon EKS using GitOps principles.

The platform combines Infrastructure as Code, GitOps continuous delivery,
Policy-as-Code security, and full-stack observability into a single cohesive
system. It is designed around the premise that security and operations
concerns should be automated and enforced at the platform level — not left
to individual application teams.

---

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Cloud | AWS (ap-southeast-1) | Infrastructure provider |
| Infrastructure as Code | Terraform 1.10+ | Provision and manage all AWS resources |
| Container Platform | Amazon EKS 1.33 | Managed Kubernetes control plane |
| Container Registry | Amazon ECR | Private image registry with vulnerability scanning |
| GitOps | ArgoCD | Declarative continuous delivery to Kubernetes |
| Configuration | Kustomize | Environment-specific manifest overlays |
| Policy Enforcement | OPA Gatekeeper | Admission control — block non-compliant resources |
| Runtime Security | Falco | eBPF-based runtime threat detection |
| Monitoring | Prometheus + Grafana | Metrics collection and visualization |
| Alerting | Alertmanager | Alert routing and deduplication |
| Database | Amazon RDS PostgreSQL 15 | Managed relational database |
| Load Balancing | AWS Load Balancer Controller | Dynamic ALB provisioning from Ingress resources |
| CI/CD | GitHub Actions | Automated pipelines for IaC and application delivery |
| Secret Management | GitHub Secrets + OIDC | Credential-free AWS authentication |
| Application | Online Boutique | Google's microservices demo (12 services) |

---

## Platform Phases

The platform is built and deployed in five sequential phases. Each phase
has a clear input, output, and set of responsibilities.

```
Phase 1 — Bootstrap
  Input:   Empty AWS account + GitHub repository
  Output:  S3 bucket, DynamoDB table, KMS key for Terraform state
  Who:     One-time manual setup by the platform engineer

Phase 2 — Infrastructure (Terraform)
  Input:   Bootstrap resources + Terraform modules
  Output:  VPC, EKS cluster, ECR, RDS, IAM roles, ArgoCD installed
  Who:     Terraform CD pipeline (workflow_dispatch)

Phase 3 — GitOps Setup (ArgoCD)
  Input:   Running EKS cluster + Git repository content
  Output:  All platform tools deployed and healthy (LBC, Gatekeeper, Falco, Prometheus, Grafana)
  Who:     ArgoCD (triggered automatically by Terraform bootstrap module)

Phase 4 — CI Pipeline (GitHub Actions)
  Input:   Pull request with code changes
  Output:  Security scan results, plan validation, PR comment with findings
  Who:     Automated on every PR

Phase 5 — CD Pipeline (GitHub Actions)
  Input:   Approved code merged to main
  Output:  New container image in ECR, Kustomize image tag updated, ArgoCD syncs
  Who:     Manual trigger via workflow_dispatch
```

---

## Repository Structure

```
aws-eks-devsecops-platform/
├── .github/workflows/          # CI/CD pipelines (5 workflows)
├── microservices-application/  # Online Boutique source code (12 services)
├── platform/
│   ├── gitops/                 # ArgoCD manifests + Kustomize configs
│   ├── infrastructure/         # Terraform modules and environments
│   └── observability/          # Operational runbooks
├── docs/                       # Architecture documentation and diagrams
└── policies/                   # Root-level OPA policies
```

The repository follows a **monorepo** structure — infrastructure code,
application manifests, and GitOps configuration all live together.
See [ADR-001](decisions/ADR-001-monorepo.md) for the rationale.

---

## Key Design Principles

**Declarative over imperative.** Every resource — from AWS VPCs to
Kubernetes deployments — is declared in code and version-controlled.
The actual state of the system is always derivable from the repository.

**Security is a platform concern, not an application concern.** OPA
Gatekeeper enforces security policies at admission time before any pod
runs. Falco monitors runtime behavior. These controls are invisible to
application teams — they just work.

**Immutable infrastructure.** Containers are never patched in place.
A code change produces a new image, which is deployed via a rolling
update. The old image is discarded.

**Everything through Git.** No engineer ever `kubectl apply`s directly
to the cluster after initial bootstrap. All changes go through Git,
triggering ArgoCD sync. The cluster is always a reflection of the
repository.

**Least privilege everywhere.** IAM roles are scoped to the minimum
permissions required. IRSA (IAM Roles for Service Accounts) ensures
each Kubernetes workload has its own identity — no shared credentials.

---

## Traffic Flow

```
User (internet)
      |
      v
AWS Application Load Balancer
  (created dynamically by AWS Load Balancer Controller when Ingress is applied)
      |
      v
frontend Service (ClusterIP)
      |
      v
frontend Pod (Go HTTP server, port 8080)
      |
      +-- productcatalogservice:3550  (gRPC)
      +-- currencyservice:7000        (gRPC)
      +-- cartservice:7070            (gRPC) --> redis-cart:6379
      +-- recommendationservice:8080  (gRPC) --> productcatalogservice:3550
      +-- checkoutservice:5050        (gRPC) --> paymentservice, shippingservice,
      |                                          emailservice, currencyservice,
      |                                          cartservice, productcatalogservice
      +-- adservice:9555              (gRPC)
      +-- shoppingassistantservice:80 (HTTP)
```

All inter-service communication is within the `online-boutique` namespace
using Kubernetes ClusterIP Services. No service is directly reachable from
outside the cluster except `frontend` via the ALB.
