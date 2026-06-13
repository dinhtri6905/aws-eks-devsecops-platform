# Cloud-Native Secure GitOps Platform on AWS EKS

## Overview

Cloud-Native Secure GitOps Platform on AWS EKS is an end-to-end DevOps and Platform Engineering project that demonstrates how to build, secure, deploy, and operate cloud-native applications on Amazon EKS using GitOps principles.

The platform provisions AWS infrastructure with Terraform, deploys applications through ArgoCD, enforces security policies using OPA Gatekeeper, monitors workloads with Prometheus and Grafana, and provides runtime threat detection through Falco.

This project follows modern Platform Engineering practices and showcases Infrastructure as Code (IaC), GitOps, Kubernetes Security, Observability, and Continuous Delivery in a production-inspired environment.

---

## Architecture

### Infrastructure Layer

* Amazon VPC
* Public & Private Subnets
* NAT Gateway
* Security Groups
* IAM Roles & Policies
* Amazon EKS Cluster
* Amazon ECR
* Application Load Balancer (ALB)
* Amazon RDS

### GitOps Layer

* ArgoCD
* Kustomize
* Environment-based deployment strategy
* Automated application synchronization

### Security Layer

* OPA Gatekeeper
* Kubernetes Policy Enforcement
* Falco Runtime Security
* Container Security Best Practices

### Observability Layer

* Prometheus Metrics Collection
* Grafana Dashboards
* Kubernetes Monitoring
* Infrastructure Monitoring

### Application Layer

* Cloud-Native Microservices
* Online Boutique Application
* Containerized Workloads
* Kubernetes Deployments

---

## Key Features

### Infrastructure as Code (Terraform)

* Modular Terraform architecture
* Reusable infrastructure modules
* Environment isolation (Dev / Prod)
* Remote State Management
* Version-controlled infrastructure

### GitOps Continuous Delivery

* Declarative Kubernetes deployments
* Automated synchronization with Git repositories
* Drift detection and self-healing
* Environment promotion workflow

### Kubernetes Security

* Policy-as-Code with OPA Gatekeeper
* Admission Control Enforcement
* Runtime Threat Detection using Falco
* Least-Privilege IAM Design

### Observability

* Cluster Monitoring
* Application Monitoring
* Resource Utilization Dashboards
* Alerting-ready Architecture

### Production-Oriented Design

* Multi-environment deployment
* Secure networking architecture
* High availability design principles
* Scalable Kubernetes platform

---

## Project Structure

```bash
aws-eks-devsecops-platform/
├── .github/
│   └── workflows/
│
├── docs/
│   ├── architecture/
│   ├── diagrams/
│   └── images/
│
├── microservices-application/
│   └── online-boutique/
│
└── platform/
    ├── infrastructure/
    │   └── terraform/
    │       ├── bootstrap/
    │       ├── environments/
    │       │   ├── dev/
    │       │   └── prod/
    │       └── modules/
    │           ├── vpc/
    │           ├── eks/
    │           ├── ecr/
    │           ├── alb/
    │           ├── rds/
    │           ├── iam/
    │           └── security-group/
    │
    ├── gitops/
    │   ├── argocd/
    │   │   ├── root-app.yaml
    │   │   ├── projects.yaml
    │   │   └── applications/
    │   │       ├── platform-services.yaml
    │   │       ├── security.yaml
    │   │       ├── observability.yaml
    │   │       └── online-boutique.yaml
    │   │
    │   └── kustomize/
    │       ├── base/
    │       │   ├── namespace.yaml
    │       │   ├── common-labels.yaml
    │       │   └── kustomization.yaml
    │       │
    │       ├── platform-services/
    │       │   ├── metrics-server/
    │       │   │   ├── kustomization.yaml
    │       │   │   └── values.yaml
    │       │   └── aws-load-balancer-controller/
    │       │       ├── kustomization.yaml
    │       │       └── values.yaml
    │       │
    │       ├── security/
    │       │   ├── opa-gatekeeper/
    │       │   │   ├── kustomization.yaml
    │       │   │   ├── values.yaml
    │       │   │   └── constraints/
    │       │   │       ├── require-resource-limits.yaml
    │       │   │       ├── require-non-root.yaml
    │       │   │       ├── disallow-privileged.yaml
    │       │   │       └── require-labels.yaml
    │       │   └── falco/
    │       │       ├── configmap.yaml
    │       │       ├── daemonset.yaml
    │       │       └── kustomization.yaml
    │       │
    │       ├── observability/
    │       │   ├── prometheus/
    │       │   │   ├── deployment.yaml
    │       │   │   ├── service.yaml
    │       │   │   └── kustomization.yaml
    │       │   └── grafana/
    │       │       ├── deployment.yaml
    │       │       ├── service.yaml
    │       │       ├── dashboards/
    │       │       └── kustomization.yaml
    │       │
    │       ├── applications/
    │       │   └── online-boutique/
    │       │       ├── adservice/
    │       │       ├── cartservice/
    │       │       ├── frontend/
    │       │       ├── productcatalog/
    │       │       ├── checkoutservice/
    │       │       ├── paymentservice/
    │       │       ├── shippingservice/
    │       │       └── kustomization.yaml
    │       │
    │       └── overlays/
    │           ├── dev/
    │           │   ├── kustomization.yaml
    │           │   ├── replicas-patch.yaml
    │           │   └── configmap-patch.yaml
    │           └── prod/
    │               ├── kustomization.yaml
    │               ├── replicas-patch.yaml
    │               ├── hpa.yaml
    │               └── resource-limits-patch.yaml
    │
    ├── security/
    │   ├── opa/
    │   └── falco/
    │
    └── observability/
        ├── prometheus/
        └── grafana/
```

---

## Technology Stack

| Category                 | Technologies                  |
| ------------------------ | ----------------------------- |
| Cloud Platform           | AWS                           |
| Infrastructure as Code   | Terraform                     |
| Container Platform       | Kubernetes (Amazon EKS)       |
| Container Registry       | Amazon ECR                    |
| GitOps                   | ArgoCD                        |
| Configuration Management | Kustomize                     |
| Security                 | OPA Gatekeeper, Falco         |
| Monitoring               | Prometheus                    |
| Visualization            | Grafana                       |
| CI/CD                    | GitHub Actions                |
| Application              | Online Boutique Microservices |

---

## Deployment Workflow

```text
Developer
    │
    ▼
GitHub Repository
    │
    ▼
GitHub Actions
    │
    ▼
Terraform Deploys AWS Infrastructure
    │
    ▼
Amazon EKS Cluster
    │
    ▼
ArgoCD Watches Git Repository
    │
    ▼
Kustomize Manifests
    │
    ▼
Application Deployment
    │
    ▼
Prometheus + Grafana Monitoring
    │
    ▼
OPA + Falco Security Enforcement
```

---

## Learning Objectives

This project demonstrates practical experience in:

* Cloud Infrastructure Automation
* Kubernetes Platform Engineering
* GitOps Continuous Delivery
* Infrastructure Security
* Policy-as-Code
* Runtime Threat Detection
* Cloud-Native Observability
* DevOps Best Practices
* Production-Ready Kubernetes Operations

---

## Future Improvements

* External Secrets Operator
* AWS Secrets Manager Integration
* Cluster Autoscaler
* Karpenter
* Service Mesh (Istio)
* Loki & Alertmanager
* Trivy Image Scanning
* SonarQube Integration
* Multi-Region Deployment
* Disaster Recovery Strategy