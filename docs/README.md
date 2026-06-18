docs/architecture/
Tài liệu giải thích các quyết định thiết kế — người mới join đọc để hiểu hệ thống.
architecture/
├── overview.md              # Tổng quan platform, tech stack, các phase
├── infrastructure.md        # VPC design, EKS cluster, RDS, network topology
├── gitops.md                # ArgoCD App of Apps pattern, sync wave ordering
├── security.md              # Defense-in-depth layers, OPA + Falco + Trivy
├── cicd.md                  # 5 workflows, security gates, deployment strategy
└── decisions/               # Architecture Decision Records (ADRs)
    ├── ADR-001-monorepo.md
    ├── ADR-002-app-of-apps.md
    ├── ADR-003-kustomize-vs-helm.md
    ├── ADR-004-blue-green.md
    └── ADR-005-opa-gate-terraform.md


docs/diagrams/
Source file cho diagrams — không phải ảnh PNG, mà là file có thể edit được.
diagrams/
├── system-overview.drawio       # Full architecture diagram
├── network-topology.drawio      # VPC, subnets, security groups
├── gitops-flow.drawio           # Git push → ArgoCD → EKS flow
├── cicd-pipeline.drawio         # CI/CD pipeline với security gates
└── security-layers.drawio       # Defense-in-depth diagram


docs/images/
Ảnh export từ diagrams hoặc screenshots — dùng để nhúng vào README và markdown files.
images/
├── observability-flow.png       # ← bạn đã có
├── system-overview.png
├── network-topology.png
├── gitops-flow.png
├── cicd-pipeline.png
└── argocd-screenshot.png        # Screenshot ArgoCD UI sau khi deploy