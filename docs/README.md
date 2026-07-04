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