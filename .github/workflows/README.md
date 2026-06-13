.github/
└── workflows/
    ├── terraform-ci.yaml      # Có sẵn — Terraform CI (validate, tflint, tfsec, checkov)
    ├── terraform-cd.yaml      # Có sẵn — Terraform CD (plan / apply / destroy)
    ├── check-scan.yaml        # Có sẵn — Security scan định kỳ
    ├── app-ci.yaml            # Cần viết — Application CI (gitleaks, build, trivy, OPA)
    └── app-cd.yaml            # Cần viết — Application CD (build+push ECR, update kustomize)