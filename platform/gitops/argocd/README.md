```bash
platform/
└── gitops/
    │
    ├── argocd/                                    # ArgoCD App-of-Apps Pattern
    │   ├── root-app.yaml                          # Root Application, entrypoint quản lý toàn bộ GitOps
    │   ├── projects/                              # AppProject định nghĩa RBAC và phạm vi deploy
    │   │   └── platform.yaml       
    │   │
    │   └── applications/
    │       ├── platform-services.yaml             # Quản lý các cluster add-ons
    │       ├── security.yaml                      # Quản lý các security services
    │       ├── observability.yaml                 # Quản lý monitoring & logging stack
    │       └── online-boutique.yaml               # Quản lý microservices application
    │
    └── kustomize/
        │
        ├── base/                                  # Cấu hình dùng chung cho toàn cluster
        │   ├── namespace.yaml                     # Namespace mặc định
        │   ├── common-labels.yaml                 # Labels dùng chung
        │   └── kustomization.yaml                 # Root kustomization
        │
        ├── platform-services/                     # Kubernetes platform add-ons
        │   │
        │   ├── metrics-server/                    # Cung cấp CPU/Memory Metrics cho cluster
        │   │   ├── values.yaml
        │   │   └── kustomization.yaml
        │   │
        │   └── aws-load-balancer-controller/      # Tự động tạo ALB/NLB trên AWS
        │       ├── values.yaml
        │       ├── ingressclass.yaml
        │       └── kustomization.yaml
        │
        ├── security/                              # Security Layer (DevSecOps)
        │   │
        │   ├── opa-gatekeeper/                    # Policy-as-Code cho Kubernetes
        │   │   ├── values.yaml
        │   │   ├── kustomization.yaml
        │   │   │
        │   │   ├── templates/                     # ConstraintTemplate (Custom Policy)
        │   │   │   ├── k8srequiredlabels.yaml
        │   │   │   ├── k8srequiredresources.yaml
        │   │   │   ├── k8snonroot.yaml
        │   │   │   └── k8sdisallowprivileged.yaml
        │   │   │
        │   │   └── constraints/                   # Policy được áp dụng thực tế
        │   │       ├── require-labels.yaml
        │   │       ├── require-resource-limits.yaml
        │   │       ├── require-non-root.yaml
        │   │       └── disallow-privileged.yaml
        │   │
        │   └── falco/                             # Runtime Threat Detection
        │       ├── values.yaml                    # Cấu hình Falco Helm Chart
        │       └── kustomization.yaml
        │
        ├── observability/                         # Monitoring & Alerting Layer
        │   │
        │   └── kube-prometheus-stack/
        │       ├── values.yaml                    # Cấu hình Prometheus, Grafana, Alertmanager
        │       ├── kustomization.yaml
        │       │
        │       ├── dashboards/                    # Dashboard Grafana
        │       │   ├── cluster-overview.json      # Tổng quan cluster
        │       │   ├── node-metrics.json          # CPU/RAM/Disk từng node
        │       │   └── application-metrics.json   # Metrics ứng dụng
        │       │
        │       ├── alerts/                        # Luật cảnh báo Prometheus
        │       │   ├── cpu-usage.yaml
        │       │   ├── memory-usage.yaml
        │       │   └── pod-restarts.yaml
        │       │
        │       └── servicemonitors/               # Prometheus Discovery
        │           ├── kubernetes.yaml
        │           └── online-boutique.yaml
        │
        ├── applications/                          # Business Applications
        │   │
        │   └── online-boutique/                   # Google Cloud Online Boutique Demo
        │       │
        │       ├── frontend/                      # Web UI
        │       ├── productcatalogservice/         # Danh mục sản phẩm
        │       ├── recommendationservice/         # Gợi ý sản phẩm
        │       ├── cartservice/                   # Giỏ hàng
        │       ├── redis-cart/                    # Redis lưu session giỏ hàng
        │       ├── checkoutservice/               # Thanh toán đơn hàng
        │       ├── paymentservice/                # Mô phỏng xử lý thanh toán
        │       ├── shippingservice/               # Mô phỏng vận chuyển
        │       ├── currencyservice/               # Quy đổi tiền tệ
        │       ├── emailservice/                  # Gửi email xác nhận
        │       ├── adservice/                     # Quảng cáo sản phẩm
        │       ├── loadgenerator/                 # Sinh traffic phục vụ test
        │       └── kustomization.yaml
        │
        └── overlays/                              # Multi-environment Configuration
            │
            ├── dev/                               # Môi trường phát triển
            │   ├── kustomization.yaml
            │   ├── replicas-patch.yaml            # Giảm replicas tiết kiệm chi phí
            │   └── configmap-patch.yaml           # Config riêng cho dev
            │
            └── prod/                              # Môi trường production
                ├── kustomization.yaml
                ├── replicas-patch.yaml            # Scale nhiều replicas
                ├── resource-limits-patch.yaml     # Giới hạn tài nguyên
                └── hpa.yaml                       # Auto Scaling theo CPU/RAM
```