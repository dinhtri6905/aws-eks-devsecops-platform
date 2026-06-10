# aws-eks-gitops-platform

## Directory Structure

```text
aws-eks-devsecops-platform/
│
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
    │
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
    │           └── iam/
    │
    ├── gitops/
    │   ├── argocd/
    │   │   ├── applications/
    │   │   └── projects/
    │   │
    │   └── kustomize/
    │       ├── base/
    │       └── overlays/
    │           ├── dev/
    │           ├── staging/
    │           └── prod/
    │
    ├── security/
    │   ├── opa/
    │   │   ├── templates/
    │   │   └── constraints/
    │   │
    │   └── falco/
    │       ├── rules/
    │       └── values/
    │
    └── observability/
        ├── prometheus/
        │
        └── grafana/
            └── dashboards/
```