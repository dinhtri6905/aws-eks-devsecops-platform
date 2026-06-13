```bash
platform/gitops/
├── root-app.yaml
├── projects/
│   └── platform.yaml
│
├── applications/
│   ├── platform-services.yaml
│   ├── security.yaml
│   ├── observability.yaml
│   └── online-boutique.yaml
│
└── kustomize/
    ├── base/
    │   ├── namespace.yaml
    │   ├── common-labels.yaml
    │   └── kustomization.yaml
    │
    ├── platform-services/
    │   ├── metrics-server/
    │   │   ├── kustomization.yaml
    │   │   └── values.yaml
    │   │
    │   └── aws-load-balancer-controller/
    │       ├── kustomization.yaml
    │       ├── values.yaml
    │       └── ingressclass.yaml
    │
    ├── security/
    │   ├── opa-gatekeeper/
    │   │   ├── kustomization.yaml
    │   │   ├── values.yaml
    │   │   ├── templates/
    │   │   └── constraints/
    │   │       ├── require-resource-limits.yaml
    │   │       ├── require-non-root.yaml
    │   │       ├── disallow-privileged.yaml
    │   │       └── require-labels.yaml
    │   │
    │   └── falco/
    │       ├── kustomization.yaml
    │       ├── configmap.yaml
    │       └── daemonset.yaml
    │
    ├── observability/
    │   └── kube-prometheus-stack/
    │       ├── kustomization.yaml
    │       ├── values.yaml
    │       ├── dashboards/
    │       │   ├── cluster-overview.json
    │       │   ├── node-metrics.json
    │       │   └── application-metrics.json
    │       │
    │       ├── alerts/
    │       │   ├── cpu-usage.yaml
    │       │   ├── memory-usage.yaml
    │       │   └── pod-restarts.yaml
    │       │
    │       └── servicemonitors/
    │           ├── kubernetes.yaml
    │           └── custom-apps.yaml
    │
    ├── applications/
    │   └── online-boutique/
    │       ├── adservice/
    │       ├── cartservice/
    │       ├── frontend/
    │       ├── productcatalogservice/
    │       ├── checkoutservice/
    │       ├── paymentservice/
    │       ├── shippingservice/
    │       ├── recommendationservice/
    │       ├── currencyservice/
    │       ├── emailservice/
    │       ├── loadgenerator/
    │       └── kustomization.yaml
    │
    └── overlays/
        ├── dev/
        │   ├── kustomization.yaml
        │   ├── replicas-patch.yaml
        │   └── configmap-patch.yaml
        │
        └── prod/
            ├── kustomization.yaml
            ├── replicas-patch.yaml
            ├── hpa.yaml
            └── resource-limits-patch.yaml
```

```bash
platform/gitops/
├── root-app.yaml
# 👉 ArgoCD App-of-Apps entry point
# 👉 Deploy toàn bộ hệ thống GitOps từ 1 root
# 👉 Trỏ xuống: applications/*

├── projects/
│   └── platform.yaml
# 👉 ArgoCD Project
# 👉 Define security boundary:
#    - repo allowed
#    - namespace allowed
#    - cluster scope
# 👉 Kiểm soát quyền deploy trong ArgoCD

│
├── applications/
│   ├── platform-services.yaml
# 👉 ArgoCD Application
# 👉 Deploy cluster add-ons:
#    - metrics-server (HPA metrics)
#    - aws-load-balancer-controller (ALB/NLB AWS)
# 👉 nền tảng cho toàn cluster

│   ├── security.yaml
# 👉 ArgoCD Application
# 👉 Deploy security layer:
#    - OPA Gatekeeper (policy enforcement)
#    - Falco (runtime security detection)
# 👉 đảm bảo cluster compliance + security

│   ├── observability.yaml
# 👉 ArgoCD Application
# 👉 Deploy monitoring stack:
#    - Prometheus (metrics collection)
#    - Grafana (dashboard visualization)
# 👉 theo dõi toàn bộ cluster + app

│   └── online-boutique.yaml
# 👉 ArgoCD Application
# 👉 Deploy microservices application
# 👉 phụ thuộc platform-services + security + observability

│
└── kustomize/

    ├── base/
    │   ├── namespace.yaml
    # 👉 tạo Kubernetes namespaces
    # 👉 tách môi trường (dev/prod/monitoring/security)

    │   ├── common-labels.yaml
    # 👉 inject labels chuẩn:
    #    app, env, team, managed-by
    # 👉 phục vụ:
    #    - tracking
    #    - observability
    #    - governance

    │   └── kustomization.yaml
    # 👉 gom base resources lại để reuse

    │
    ├── platform-services/

    │   ├── metrics-server/
    │   │   ├── kustomization.yaml
    # 👉 định nghĩa cách deploy metrics-server
    # 👉 phục vụ HPA (autoscaling CPU/Memory)

    │   │   └── values.yaml
    # 👉 config Helm chart metrics-server
    # 👉 không tự viết deployment thủ công

    │
    │   └── aws-load-balancer-controller/
    │       ├── kustomization.yaml
    # 👉 deploy AWS LB controller bằng ArgoCD

    │       ├── values.yaml
    # 👉 config Helm chart:
    #    - IAM role (IRSA)
    #    - cluster name
    #    - region

    │       └── ingressclass.yaml
    # 👉 định nghĩa IngressClass "alb"
    # 👉 mapping Ingress → AWS Load Balancer Controller
    # 👉 KHÔNG tạo ALB trực tiếp, chỉ route rule

    │
    ├── security/

    │   ├── opa-gatekeeper/
    │   │   ├── kustomization.yaml
    # 👉 deploy OPA Gatekeeper controller

    │   │   ├── values.yaml
    # 👉 Helm config cho policy engine

    │   │   ├── templates/
    # 👉 định nghĩa policy schema (logic rules)

    │   │   └── constraints/
    # 👉 áp dụng policy vào cluster:
    #    - require limits
    #    - non-root container
    #    - no privileged container
    #    - required labels

    │
    │   └── falco/
    │       ├── kustomization.yaml
    # 👉 deploy Falco runtime security

    │       ├── configmap.yaml
    # 👉 rule detection config:
    #    - suspicious syscall
    #    - abnormal container behavior

    │       └── daemonset.yaml
    # 👉 chạy trên EVERY node
    # 👉 monitor runtime security events
    │
    ├── applications/
    │   └── online-boutique/
    │       ├── adservice/
    # 👉 microservice quảng cáo / recommendation

    │       ├── cartservice/
    # 👉 quản lý giỏ hàng

    │       ├── frontend/
    # 👉 UI web application

    │       ├── productcatalogservice/
    # 👉 database product service

    │       ├── checkoutservice/
    # 👉 xử lý checkout flow

    │       ├── paymentservice/
    # 👉 xử lý payment logic (mock)

    │       ├── shippingservice/
    # 👉 tính shipping

    │       ├── recommendationservice/
    # 👉 gợi ý sản phẩm

    │       ├── currencyservice/
    # 👉 chuyển đổi tiền tệ

    │       ├── emailservice/
    # 👉 gửi email notification

    │       ├── loadgenerator/
    # 👉 generate traffic để test system

    │       └── kustomization.yaml
    # 👉 gom toàn bộ microservices lại để deploy

    │
    └── overlays/

        ├── dev/
        │   ├── kustomization.yaml
        # 👉 override config cho môi trường dev
        # 👉 dùng cho testing / development

        │   ├── replicas-patch.yaml
        # 👉 giảm replica (tiết kiệm tài nguyên)

        │   └── configmap-patch.yaml
        # 👉 bật debug, log level verbose

        │
        └── prod/
            ├── kustomization.yaml
            # 👉 production environment config

            ├── replicas-patch.yaml
            # 👉 scale replicas cao (HA)

            ├── hpa.yaml
            # 👉 autoscaling policy (CPU/Memory)

            └── resource-limits-patch.yaml
                # 👉 enforce CPU/Memory limits
                # 👉 tránh resource abuse + đảm bảo stability
```