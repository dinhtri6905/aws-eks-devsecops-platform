```bash
platform/gitops/
├── root-app.yaml
# 👉 ArgoCD App-of-Apps root
# 👉 Entry point duy nhất để sync toàn bộ system
# 👉 Nó sẽ trỏ xuống applications/*

│
├── projects/
│   └── platform.yaml
# 👉 ArgoCD Project
# 👉 Define:
#    - namespace allowed
#    - repo allowed
#    - cluster scope
# 👉 Security boundary cho GitOps

│
├── applications/
│
│   ├── platform-services.yaml
# 👉 ArgoCD Application
# 👉 Deploy infra tools:
#    - metrics-server
#    - aws-load-balancer-controller
# 👉 thường dùng Helm hoặc Kustomize
# 👉 chạy trước app

│
│   ├── security.yaml
# 👉 ArgoCD Application
# 👉 Deploy security layer:
#    - OPA Gatekeeper
#    - Falco
# 👉 enforce policy + runtime security

│
│   ├── observability.yaml
# 👉 ArgoCD Application
# 👉 Deploy monitoring stack:
#    - Prometheus
#    - Grafana
# 👉 collect metrics + dashboards

│
│   └── online-boutique.yaml
# 👉 ArgoCD Application
# 👉 Deploy microservices app demo
# 👉 depends on platform-services + security + observability

│
└── kustomize/
    # ======================================================
    # 1. BASE LAYER (shared config)
    # ======================================================
    ├── base/
    │   ├── namespace.yaml
    # 👉 define Kubernetes namespaces
    # 👉 ví dụ: dev, prod, monitoring, security
    # 👉 tách workload isolation

    │
    │   ├── common-labels.yaml
    # 👉 inject labels chung:
    #    app, env, team, managed-by
    # 👉 giúp:
    #    - monitoring
    #    - cost tracking
    #    - governance

    │
    │   └── kustomization.yaml
    # 👉 base aggregator
    # 👉 gom namespace + labels + shared config

    # ======================================================
    # 2. PLATFORM SERVICES (Cluster Add-ons)
    # ======================================================

    ├── platform-services/

    │   ├── metrics-server/
    │   │   ├── deployment.yaml
    # 👉 Metrics API cho HPA (autoscaling)
    # 👉 cung cấp CPU/Memory metrics cho cluster

    │   │   ├── service.yaml
    # 👉 expose metrics-server service

    │   │   └── kustomization.yaml
    # 👉 build metrics-server stack

    │
    │   └── aws-load-balancer-controller/
    │       ├── deployment.yaml
    # 👉 controller tạo ALB/NLB trên AWS
    # 👉 đọc Ingress → tạo Load Balancer

    │       ├── service.yaml
    # 👉 service cho controller pods

    │       ├── ingressclass.yaml
    # 👉 define ingress class: alb
    # 👉 map ingress → AWS ALB

    │       └── kustomization.yaml
    # 👉 bundle toàn bộ AWS LB controller

    # ======================================================
    # 3. SECURITY LAYER
    # ======================================================

    ├── security/

    │   ├── opa-gatekeeper/
    │   │   ├── templates/
    # 👉 constraint templates (logic rule engine)
    # 👉 define policy schema

    │   │   ├── constraints/
    │   │   │   ├── require-resource-limits.yaml
    # 👉 bắt container phải có CPU/RAM limits

    │   │   │   ├── require-non-root.yaml
    # 👉 cấm chạy container bằng root user

    │   │   │   ├── disallow-privileged.yaml
    # 👉 cấm privileged container (host access)

    │   │   │   └── require-labels.yaml
    # 👉 bắt resource phải có labels chuẩn

    │   │   └── kustomization.yaml
    # 👉 deploy Gatekeeper + policies

    │
    │   └── falco/
    │       ├── configmap.yaml
    # 👉 config rule detection (syscall rules)
    # 👉 detect suspicious behavior

    │       ├── daemonset.yaml
    # 👉 run Falco on every node
    # 👉 collect runtime security events

    │       └── kustomization.yaml
    # 👉 deploy Falco system

    # ======================================================
    # 4. OBSERVABILITY STACK
    # ======================================================

    ├── observability/

    │   ├── prometheus/
    │   │   ├── deployment.yaml
    # 👉 Prometheus server
    # 👉 scrape metrics từ cluster + apps

    │   │   ├── service.yaml
    # 👉 expose Prometheus UI/API

    │   │   └── kustomization.yaml
    # 👉 deploy monitoring backend

    │
    │   └── grafana/
    │       ├── deployment.yaml
    # 👉 Grafana UI dashboard

    │       ├── service.yaml
    # 👉 expose Grafana UI

    │       ├── dashboards/
    # 👉 JSON dashboards:
    #    - cluster metrics
    #    - pod CPU/RAM
    #    - app latency

    │       └── kustomization.yaml
    # 👉 bundle Grafana config

    # ======================================================
    # 5. APPLICATION LAYER (MICROSERVICES)
    # ======================================================

    ├── applications/
    │   └── online-boutique/

    │       ├── adservice/
    # 👉 ads microservice (recommendation ads)

    │       ├── cartservice/
    # 👉 shopping cart logic

    │       ├── frontend/
    # 👉 UI web app

    │       ├── productcatalog/
    # 👉 product database service

    │       ├── checkoutservice/
    # 👉 checkout workflow

    │       ├── paymentservice/
    # 👉 payment simulation

    │       ├── shippingservice/
    # 👉 shipping calculation

    │       └── kustomization.yaml
    # 👉 gom tất cả microservices lại
    # 👉 define deployment + service + config

    # ======================================================
    # 6. ENVIRONMENT OVERLAYS
    # ======================================================

    └── overlays/

        ├── dev/
        │   ├── kustomization.yaml
        # 👉 override base cho DEV environment
        # 👉 thường:
        #    - replicas thấp
        #    - debug enabled

        │   ├── replicas-patch.yaml
        # 👉 set replicas = 1

        │   └── configmap-patch.yaml
        # 👉 dev config:
        #    - log level debug
        #    - test endpoints

        │
        └── prod/
            ├── kustomization.yaml
            # 👉 production overlay
            # 👉 stable config

            ├── replicas-patch.yaml
            # 👉 scale replicas (HA)

            ├── hpa.yaml
            # 👉 autoscaling config
            # 👉 CPU/Memory based scaling

            └── resource-limits-patch.yaml
                # 👉 enforce CPU/Memory limits
                # 👉 prevent resource abuse
```