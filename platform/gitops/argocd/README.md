```bash
platform/gitops/
├── root-app.yaml
│
├── applications/
│   ├── platform-services.yaml
│   ├── security.yaml
│   ├── observability.yaml
│   └── online-boutique.yaml
│
├── projects/
│   └── platform.yaml
│
└── kustomize/
    ├── base/
    │   ├── namespace.yaml
    │   ├── common-labels.yaml
    │   └── kustomization.yaml
    │
    ├── platform-services/
    │   ├── metrics-server/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── kustomization.yaml
    │   │
    │   └── aws-load-balancer-controller/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       ├── ingressclass.yaml
    │       └── kustomization.yaml
    │
    ├── security/
    │   ├── opa-gatekeeper/
    │   │   ├── templates/
    │   │   ├── constraints/
    │   │   └── kustomization.yaml
    │   │
    │   └── falco/
    │       ├── configmap.yaml
    │       ├── daemonset.yaml
    │       └── kustomization.yaml
    │
    ├── observability/
    │   ├── prometheus/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── kustomization.yaml
    │   │
    │   └── grafana/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       ├── dashboards/
    │       └── kustomization.yaml
    │
    ├── applications/
    │   └── online-boutique/
    │       ├── adservice/
    │       ├── cartservice/
    │       ├── frontend/
    │       ├── productcatalog/
    │       ├── checkoutservice/
    │       ├── paymentservice/
    │       ├── shippingservice/
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