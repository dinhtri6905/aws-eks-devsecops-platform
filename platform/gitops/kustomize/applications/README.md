# platform/gitops/kustomize/applications/online-boutique

Base Kubernetes manifests for all 13 Online Boutique workloads. This layer defines the application as it runs without any environment-specific tuning — `overlays/dev/` and `overlays/prod/` both build on top of it via Kustomize `bases`, applying replica counts, resource limits, and environment config as patches rather than duplicating these manifests per environment.

This directory has no ArgoCD Application of its own — it is never synced directly. ArgoCD's `online-boutique` Application (sync-wave "4", the last wave) points at the environment overlay, which in turn references this base.

---

## Directory Structure

```text
applications/online-boutique/
├── kustomization.yaml          # Aggregator — lists all 13 service directories, sets namespace + commonLabels
│
├── frontend/                   # deployment.yaml, service.yaml, ingress.yaml
├── adservice/                  # deployment.yaml, service.yaml
├── cartservice/                # deployment.yaml, service.yaml
├── checkoutservice/            # deployment.yaml, service.yaml
├── currencyservice/            # deployment.yaml, service.yaml
├── emailservice/                # deployment.yaml, service.yaml
├── paymentservice/             # deployment.yaml, service.yaml
├── productcatalogservice/      # deployment.yaml, service.yaml
├── recommendationservice/      # deployment.yaml, service.yaml
├── shippingservice/            # deployment.yaml, service.yaml
├── shoppingassistantservice/   # deployment.yaml, service.yaml
├── redis-cart/                  # deployment.yaml, service.yaml
└── loadgenerator/               # deployment.yaml (no Service — outbound traffic only)
```

Every service directory follows the same two-or-three-file pattern: a `Deployment`, a `ClusterIP` `Service`, and — for `frontend` only — an `Ingress`.

---

## Workloads

| Service | Image | Port | Protocol |
|---|---|---|---|
| `frontend` | `gcr.io/google-samples/microservices-demo/frontend:v0.10.0` | 8080 (`http`) | HTTP, exposed externally via `Ingress` |
| `adservice` | `gcr.io/google-samples/microservices-demo/adservice:v0.10.0` | 9555 (`grpc`) | gRPC |
| `cartservice` | `gcr.io/google-samples/microservices-demo/cartservice:v0.10.0` | 7070 | gRPC |
| `checkoutservice` | `gcr.io/google-samples/microservices-demo/checkoutservice:v0.10.0` | 5050 (`grpc`) | gRPC |
| `currencyservice` | `gcr.io/google-samples/microservices-demo/currencyservice:v0.10.0` | 7000 (`grpc`) | gRPC |
| `emailservice` | `gcr.io/google-samples/microservices-demo/emailservice:v0.10.0` | 8080 (`grpc`) | gRPC |
| `paymentservice` | `gcr.io/google-samples/microservices-demo/paymentservice:v0.10.0` | 50051 (`grpc`) | gRPC |
| `productcatalogservice` | `gcr.io/google-samples/microservices-demo/productcatalogservice:v0.10.0` | 3550 | gRPC |
| `recommendationservice` | `gcr.io/google-samples/microservices-demo/recommendationservice:v0.10.0` | 8080 (`grpc`) | gRPC |
| `shippingservice` | `gcr.io/google-samples/microservices-demo/shippingservice:v0.10.0` | 50051 (`grpc`) | gRPC |
| `shoppingassistantservice` | `gcr.io/google-samples/microservices-demo/shoppingassistantservice:v0.10.0` | 80 | HTTP |
| `redis-cart` | `redis:alpine` | 6379 | TCP |
| `loadgenerator` | `gcr.io/google-samples/microservices-demo/loadgenerator:v0.10.0` | — | HTTP (outbound only) |

All manifests pin the Google-published `v0.10.0` upstream images as the base state. The application CD pipeline (`app-cd.yaml`) overwrites these with ECR-hosted, SHA-tagged images for whichever services changed, via `kustomize edit set image` against this same directory.

`loadgenerator` carries an `initContainer` (`busybox:1.35`) that polls `frontend` until it responds, so the load generator never starts hammering an endpoint that isn't ready yet.

---

## Workload Configuration

Every `Deployment` in this layer follows the same baseline, written to satisfy the OPA Gatekeeper constraints enforced cluster-wide:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
    resources:
      requests: { cpu: ..., memory: ... }
      limits:    { cpu: ..., memory: ... }
```

`frontend` additionally defines `readinessProbe` and `livenessProbe` HTTP checks against `/_healthz`, and carries the environment variables that point it at every backend service it depends on (`PRODUCT_CATALOG_SERVICE_ADDR`, `CART_SERVICE_ADDR`, `CHECKOUT_SERVICE_ADDR`, and so on) — these are the same addresses shown in the service communication flow in the top-level README.

### Ingress

Only `frontend/ingress.yaml` defines an `Ingress`, since it is the platform's single external entry point. It targets the `alb` `IngressClass` (created in `platform-services/aws-load-balancer-controller/`) and is annotated for an internet-facing ALB with IP target mode and a health check against `/_healthz`:

```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/healthcheck-path: /_healthz
```

---

## Service Communication

`cartservice` is the only service with a stateful dependency — it talks to `redis-cart` over TCP on port 6379 for cart persistence. Every other inter-service call uses gRPC over the cluster's internal DNS (`<service>.online-boutique.svc.cluster.local`), following the call graph documented in the top-level project README's Application Architecture section.

---

## How Environments Differ

This directory contains no environment-specific values — no replica counts, no `ENVIRONMENT` variable, no HPA. Those are layered on entirely by the overlays:

```text
applications/online-boutique/  (this directory — base manifests)
        ▲                    ▲
        │                    │
  overlays/dev/         overlays/prod/
  (1 replica,            (2+ replicas,
   debug config)          HPA, stricter limits)
```

See `overlays/README.md` for what each overlay patches.
