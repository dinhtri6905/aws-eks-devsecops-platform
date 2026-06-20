# Kế hoạch triển khai Blue-Green — AWS EKS DevSecOps Platform

> **Phạm vi áp dụng:** 10 microservices của Online Boutique (trừ `redis-cart`)  
> **Công nghệ cốt lõi:** Argo Rollouts + ArgoCD App of Apps + Kustomize overlays  
> **Thời gian ước tính:** 3 tuần

---

## Mục lục

1. [Tổng quan & Nguyên lý hoạt động](#1-tổng-quan--nguyên-lý-hoạt-động)
2. [Hiện trạng cần thay đổi](#2-hiện-trạng-cần-thay-đổi)
3. [Giai đoạn 1 — Cài đặt Argo Rollouts vào platform](#giai-đoạn-1--cài-đặt-argo-rollouts-vào-platform-tuần-1)
4. [Giai đoạn 2 — Chuyển đổi manifest sang Rollout](#giai-đoạn-2--chuyển-đổi-manifest-sang-rollout-tuần-2)
5. [Giai đoạn 3 — Tích hợp CI/CD Pipeline](#giai-đoạn-3--tích-hợp-cicd-pipeline-tuần-2-3)
6. [Giai đoạn 4 — Observability & Rollback](#giai-đoạn-4--observability--rollback-tuần-3)
7. [Thứ tự migrate các service](#7-thứ-tự-migrate-các-service)
8. [Bảng tóm tắt công việc](#8-bảng-tóm-tắt-công-việc)

---

## 1. Tổng quan & Nguyên lý hoạt động

### Blue-Green là gì?

Blue-Green deployment là chiến lược triển khai chạy **hai môi trường song song** — Blue (đang phục vụ production) và Green (phiên bản mới vừa deploy). Khi Green được xác nhận healthy, toàn bộ traffic được chuyển sang Green trong một lần. Blue được giữ lại trong một khoảng thời gian ngắn để rollback tức thì nếu cần.

```
          ┌─────────────────────────────┐
          │         AWS ALB              │
          │  100% traffic → active svc  │
          └────────┬────────────────────┘
                   │
       ┌───────────▼────────────┐
       │   frontend-active (svc)│  ← production traffic
       └───────────┬────────────┘
                   │
    ┌──────────────▼──────────────────────────┐
    │          Argo Rollouts Controller        │
    │                                         │
    │   🔵 Blue ReplicaSet   🟢 Green ReplicaSet│
    │   (version cũ, active) (version mới)    │
    └─────────────────────────────────────────┘
```

Trong quá trình deploy:
1. Green ReplicaSet được tạo ra với image mới
2. `frontend-preview` service trỏ vào Green để QA/smoke test
3. Khi approve, `frontend-active` service chuyển selector sang Green
4. Blue ReplicaSet giữ nguyên trong 5 phút (để rollback nếu cần)
5. Sau 5 phút, Blue tự động bị scale down

### Tại sao dùng Argo Rollouts thay vì tự làm?

Argo Rollouts là Kubernetes controller chuyên biệt, tích hợp sẵn với ArgoCD (đã có trong platform). Nó cung cấp:
- Quản lý vòng đời Blue/Green hoàn chỉnh qua CRD `Rollout`
- `kubectl argo rollouts` CLI để promote/abort/undo
- UI trực quan trong ArgoCD Dashboard
- `AnalysisTemplate` để tự động kiểm tra metrics trước khi promote

---

## 2. Hiện trạng cần thay đổi

### Vấn đề hiện tại

Tất cả 11 service đang dùng `kind: Deployment` thông thường (file `deployment.yaml` trong mỗi thư mục service). Khi ArgoCD sync image mới, Kubernetes dùng `RollingUpdate` mặc định — không có cơ chế kiểm soát, không có preview environment, không có rollback tức thì.

### Danh sách service cần migrate

| Service | Port/Protocol | Ghi chú |
|---|---|---|
| `frontend` | 8080 / HTTP | Có Ingress ALB, cần đặc biệt chú ý |
| `cartservice` | 7070 / gRPC | HPA đang trỏ vào Deployment |
| `checkoutservice` | 5050 / gRPC | HPA đang trỏ vào Deployment |
| `productcatalogservice` | 3550 / gRPC | HPA đang trỏ vào Deployment |
| `currencyservice` | 7000 / gRPC | |
| `paymentservice` | 50051 / gRPC | |
| `shippingservice` | 50051 / gRPC | |
| `emailservice` | 5000 / gRPC | |
| `recommendationservice` | 8080 / gRPC | |
| `adservice` | 9555 / gRPC | |

> ⚠️ **`redis-cart` KHÔNG migrate** — đây là stateful workload (có volume `redis-data`), Blue-Green không phù hợp. Giữ nguyên `kind: Deployment`.

### Thứ tự ưu tiên migrate

```
Đợt 1 (tuần 2): frontend → checkoutservice → cartservice
Đợt 2 (tuần 3): productcatalogservice → currencyservice → paymentservice
Đợt 3 (tuần 3): shippingservice → emailservice → recommendationservice → adservice
```

---

## Giai đoạn 1 — Cài đặt Argo Rollouts vào platform (Tuần 1)

### Mục tiêu

Cài Argo Rollouts controller lên cluster thông qua GitOps (ArgoCD platform-services), đảm bảo controller chạy trước khi bất kỳ `Rollout` resource nào được tạo.

### 1.1 — Tạo thư mục Argo Rollouts trong platform-services

**File cần tạo mới:** `platform/gitops/kustomize/platform-services/argo-rollouts/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: argo-rollouts
    repo: https://argoproj.github.io/argo-helm
    version: "2.37.6"              # Kiểm tra phiên bản mới nhất
    releaseName: argo-rollouts
    namespace: argo-rollouts
    valuesInline:
      installCRDs: true
      controller:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      dashboard:
        enabled: true              # UI xem rollout status
        service:
          type: ClusterIP
```

**File cần sửa:** `platform/gitops/kustomize/platform-services/kustomization.yaml`

```yaml
# Trước khi sửa:
resources:
  - metrics-server/
  - aws-load-balancer-controller/

# Sau khi sửa:
resources:
  - metrics-server/
  - aws-load-balancer-controller/
  - argo-rollouts/               # ← thêm dòng này
```

**Giải thích:** `platform-services` ArgoCD Application đang ở `sync-wave: "1"`, chạy trước `online-boutique` ở `sync-wave: "4"`. Nhờ đó, Argo Rollouts controller và CRD sẽ sẵn sàng trước khi các `Rollout` resource được apply.

### 1.2 — Cập nhật OPA Gatekeeper exclusions

Hiện tại, Gatekeeper đang enforce constraint `require-app-labels` cho mọi Pod trong namespace `online-boutique`. Argo Rollouts controller chạy trong namespace `argo-rollouts` — cần đảm bảo namespace này được loại trừ khỏi các constraint bảo mật.

**File cần kiểm tra và cập nhật:**  
`platform/gitops/kustomize/security/opa-gatekeeper/constraints/require-non-root.yaml`  
`platform/gitops/kustomize/security/opa-gatekeeper/constraints/require-resource-limits.yaml`  
`platform/gitops/kustomize/security/opa-gatekeeper/constraints/require-read-only-root-filesystem.yaml`

Thêm `argo-rollouts` vào `excludedNamespaces` (tương tự như `kube-system`, `argocd`, `monitoring`, `falco` đang được exclude):

```yaml
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - kube-system
      - argocd
      - monitoring
      - falco
      - argo-rollouts    # ← thêm dòng này
```

**Giải thích:** Argo Rollouts controller pod cần quyền nhất định để quản lý ReplicaSet. Nếu không exclude, Gatekeeper sẽ chặn controller pod và Rollouts sẽ không hoạt động.

### 1.3 — Verify cài đặt

Sau khi ArgoCD sync, kiểm tra:

```bash
# Kiểm tra controller đang chạy
kubectl get pods -n argo-rollouts

# Kiểm tra CRD đã được cài
kubectl get crd | grep rollout

# Kết quả mong đợi:
# rollouts.argoproj.io
# analysisruns.argoproj.io
# analysistemplates.argoproj.io
# experiments.argoproj.io
```

---

## Giai đoạn 2 — Chuyển đổi manifest sang Rollout (Tuần 2)

### Mục tiêu

Chuyển từng `kind: Deployment` sang `kind: Rollout`, tạo cặp Service `-active`/`-preview` cho mỗi service, cập nhật Ingress và HPA.

### 2.1 — Tạo cặp Service active/preview

Mỗi service hiện có 1 Service (`ClusterIP`). Blue-Green cần 2. Lấy `frontend` làm ví dụ:

**File hiện tại:** `frontend/service.yaml`
```yaml
# Hiện tại — chỉ có 1 service
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

**Sau khi sửa:** Tách thành 2 file hoặc dùng multi-document trong cùng file:

```yaml
# frontend-active: nhận 100% production traffic
apiVersion: v1
kind: Service
metadata:
  name: frontend-active
  labels:
    app: frontend
    role: active
spec:
  type: ClusterIP
  selector:
    app: frontend
    # Selector này sẽ được Argo Rollouts tự cập nhật
    # khi promote — KHÔNG cần thêm rollouts-pod-template-hash
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
# frontend-preview: nhận traffic preview cho QA/smoke test
apiVersion: v1
kind: Service
metadata:
  name: frontend-preview
  labels:
    app: frontend
    role: preview
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

> **Lưu ý quan trọng:** Argo Rollouts sẽ tự động thêm label `rollouts-pod-template-hash` vào selector của 2 service này để phân biệt Blue và Green pod. Bạn không cần (và không nên) tự thêm label đó.

**Đối với các gRPC service** (cartservice, checkoutservice, v.v.), pattern tương tự nhưng port khác:

```yaml
# cartservice-active
apiVersion: v1
kind: Service
metadata:
  name: cartservice-active
spec:
  type: ClusterIP
  selector:
    app: cartservice
  ports:
    - name: grpc
      port: 7070
      targetPort: 7070
---
# cartservice-preview
apiVersion: v1
kind: Service
metadata:
  name: cartservice-preview
spec:
  type: ClusterIP
  selector:
    app: cartservice
  ports:
    - name: grpc
      port: 7070
      targetPort: 7070
```

> **Giữ nguyên service tên cũ** (ví dụ `cartservice`) để các service khác vẫn có thể gọi qua `cartservice:7070` mà không cần đổi env var. Service cũ này sẽ từ từ deprecated sau khi toàn bộ stable.

### 2.2 — Chuyển Deployment sang Rollout

**File hiện tại:** `frontend/deployment.yaml` với `apiVersion: apps/v1`, `kind: Deployment`

**File sau khi sửa:** Thay toàn bộ phần `apiVersion`, `kind`, và `spec.strategy`:

```yaml
apiVersion: argoproj.io/v1alpha1    # ← đổi từ apps/v1
kind: Rollout                        # ← đổi từ Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  selector:
    matchLabels:
      app: frontend
  # ─── Phần strategy thay thế cho strategy: RollingUpdate ───
  strategy:
    blueGreen:
      # Service nhận production traffic (Blue)
      activeService: frontend-active
      # Service nhận preview traffic (Green)
      previewService: frontend-preview
      # false = manual approve trước khi chuyển traffic (khuyến nghị cho prod)
      # true  = tự động promote sau autoPromotionSeconds
      autoPromotionEnabled: false
      # Giữ Blue ReplicaSet trong 5 phút sau khi promote
      # → đủ thời gian rollback nếu phát hiện lỗi ngay sau promote
      scaleDownDelaySeconds: 300
      # Green chỉ chạy 1 pod lúc preview (tiết kiệm resource)
      # Sẽ scale lên đủ replicas sau khi promote
      previewReplicaCount: 1
  # ─── Phần template giữ nguyên hoàn toàn ───
  template:
    metadata:
      labels:
        app: frontend
      annotations:
        sidecar.istio.io/rewriteAppHTTPProbers: "true"
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      terminationGracePeriodSeconds: 5
      containers:
        - name: frontend
          image: gcr.io/google-samples/microservices-demo/frontend:v0.10.0
          # ... (giữ nguyên toàn bộ phần còn lại)
```

**Điểm khác biệt quan trọng so với Deployment:**

| Trường | Deployment | Rollout |
|---|---|---|
| `apiVersion` | `apps/v1` | `argoproj.io/v1alpha1` |
| `kind` | `Deployment` | `Rollout` |
| `spec.strategy` | `type: RollingUpdate` | `blueGreen: {...}` |
| `spec.replicas` | Giữ nguyên | Giữ nguyên |
| `spec.template` | Giữ nguyên | **Giữ nguyên hoàn toàn** |

### 2.3 — Cập nhật Ingress

**File hiện tại:** `frontend/ingress.yaml` đang trỏ vào `service.name: frontend`

```yaml
# Sau khi sửa — trỏ vào frontend-active
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-active    # ← đổi từ "frontend"
                port:
                  number: 80
```

**Giải thích:** ALB sẽ luôn route traffic vào `frontend-active`. Argo Rollouts controller quản lý selector của service này để quyết định traffic đang vào Blue hay Green pod.

### 2.4 — Cập nhật HPA (prod overlay)

**File hiện tại:** `overlays/prod/hpa.yaml` đang dùng `scaleTargetRef.apiVersion: apps/v1` và `kind: Deployment`

```yaml
# Trước khi sửa:
scaleTargetRef:
  apiVersion: apps/v1
  kind: Deployment
  name: frontend

# Sau khi sửa:
scaleTargetRef:
  apiVersion: argoproj.io/v1alpha1    # ← đổi
  kind: Rollout                         # ← đổi
  name: frontend
```

Áp dụng tương tự cho `cartservice-hpa`, `checkoutservice-hpa`, `productcatalogservice-hpa`.

### 2.5 — Cập nhật kustomization.yaml của từng service

**File hiện tại:** `frontend/kustomization.yaml`
```yaml
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```

**Sau khi sửa:**
```yaml
resources:
  - rollout.yaml          # ← đổi tên file (hoặc giữ deployment.yaml tùy convention)
  - service-active.yaml   # ← tách ra 2 file service
  - service-preview.yaml
  - service.yaml          # ← giữ lại để backward compat (deprecated dần)
  - ingress.yaml
```

### 2.6 — Cập nhật overlay patches

Overlay `dev` và `prod` hiện đang patch `kind: Deployment`. Cần đổi target sang `kind: Rollout`.

**File:** `overlays/dev/kustomization.yaml`
```yaml
patches:
  - path: replicas-patch.yaml
    target:
      kind: Rollout           # ← đổi từ Deployment
```

**File:** `overlays/dev/replicas-patch.yaml` — giữ nguyên nội dung, chỉ đổi `kind`:
```yaml
apiVersion: argoproj.io/v1alpha1    # ← đổi
kind: Rollout                        # ← đổi
metadata:
  name: frontend
spec:
  replicas: 1
```

**Overlay riêng cho Blue-Green behavior theo môi trường:**

Tạo thêm patch để control `autoPromotionEnabled` khác nhau giữa dev và prod:

```yaml
# overlays/dev/bluegreen-patch.yaml — tự động promote sau 2 phút
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: frontend
spec:
  strategy:
    blueGreen:
      autoPromotionEnabled: true
      autoPromotionSeconds: 120

# overlays/prod/bluegreen-patch.yaml — luôn manual approve
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: frontend
spec:
  strategy:
    blueGreen:
      autoPromotionEnabled: false
```

---

## Giai đoạn 3 — Tích hợp CI/CD Pipeline (Tuần 2-3)

### Mục tiêu

Cập nhật CI/CD pipeline để sau khi deploy image mới, pipeline có thể theo dõi trạng thái Rollout và tự động abort nếu Green unhealthy.

### 3.1 — Luồng CI/CD hiện tại

```
[Git push] → [Build + Test] → [Trivy scan] → [Push ECR] → [kustomize edit set image] → [git push]
                                                                                              ↓
                                                                                    [ArgoCD auto-sync]
                                                                                              ↓
                                                                                    [Kubernetes apply]
```

### 3.2 — Luồng CI/CD sau khi tích hợp Blue-Green

```
[Git push] → [Build + Test] → [Trivy scan] → [Push ECR] → [kustomize edit set image] → [git push]
                                                                                              ↓
                                                                                    [ArgoCD auto-sync]
                                                                                              ↓
                                                                              [Argo Rollouts: tạo Green RS]
                                                                                              ↓
                                                                            [Pipeline: watch rollout status]
                                                                                      ↙          ↘
                                                                             [Healthy]        [Degraded]
                                                                                ↓                  ↓
                                                                     [Dev: auto-promote]    [pipeline abort]
                                                                     [Prod: notify Slack]   [rollback tự động]
                                                                            ↓
                                                                   [Prod: manual approve]
```

### 3.3 — Bổ sung step vào pipeline

Trong file CI pipeline (GitHub Actions hoặc tương đương), thêm job sau bước push image:

```yaml
# Ví dụ với GitHub Actions
- name: Watch Rollout Status
  run: |
    # Cài kubectl argo rollouts plugin
    curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
    chmod +x kubectl-argo-rollouts-linux-amd64
    mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

    # Chờ ArgoCD sync hoàn tất (tối đa 3 phút)
    sleep 30

    # Xem trạng thái rollout
    kubectl argo rollouts status $SERVICE_NAME \
      -n online-boutique \
      --timeout=5m \
      --watch

    # Nếu status là Degraded → abort
    STATUS=$(kubectl argo rollouts get rollout $SERVICE_NAME -n online-boutique --no-color | grep "Status:" | awk '{print $2}')
    if [ "$STATUS" = "Degraded" ]; then
      echo "❌ Rollout degraded — aborting"
      kubectl argo rollouts abort $SERVICE_NAME -n online-boutique
      exit 1
    fi

    echo "✅ Green environment healthy"

- name: Notify for Manual Approval (Prod only)
  if: github.ref == 'refs/heads/main'
  run: |
    # Gửi notification Slack/Teams để team approve
    curl -X POST $SLACK_WEBHOOK \
      -d '{"text": "🟢 Green environment ready for *${{ env.SERVICE_NAME }}*. Approve promotion: kubectl argo rollouts promote ${{ env.SERVICE_NAME }} -n online-boutique"}'
```

### 3.4 — Manual Promote (Prod)

Khi Green đã healthy và QA đã kiểm tra xong, team approve bằng 1 lệnh:

```bash
# Promote Green → trở thành Active (toàn bộ traffic chuyển sang Green)
kubectl argo rollouts promote frontend -n online-boutique

# Xem quá trình promote realtime
kubectl argo rollouts get rollout frontend -n online-boutique --watch
```

Trong ArgoCD UI cũng có nút "Promote" nếu cài Argo Rollouts Dashboard.

---

## Giai đoạn 4 — Observability & Rollback (Tuần 3)

### Mục tiêu

Thêm visibility cho Rollout status vào Grafana, thiết lập alert, và có quy trình rollback rõ ràng.

### 4.1 — Cập nhật ServiceMonitor cho Prometheus

File hiện tại `observability/kube-prometheus-stack/servicemonitors/online-boutique.yaml` đang monitor tất cả service trong namespace. Sau khi thêm `-active` và `-preview` service, Prometheus sẽ tự động scrape cả 2 (vì `selector: matchLabels: {}` — match tất cả).

Tuy nhiên, cần thêm label phân biệt để dễ query:

```yaml
# Thêm vào ServiceMonitor endpoints
endpoints:
  - port: http
    path: /metrics
    interval: 30s
    honorLabels: true
    relabelings:
      # Thêm label "service_role" vào mỗi metric
      - sourceLabels: [__meta_kubernetes_service_label_role]
        targetLabel: service_role    # giá trị: "active" hoặc "preview"
```

### 4.2 — Thêm panel Rollout Status vào Grafana Dashboard

**File:** `observability/kube-prometheus-stack/dashboards/application-metrics.yaml`

Thêm các panel sau vào ConfigMap dashboard:

```json
{
  "title": "Blue-Green Rollout Status",
  "type": "stat",
  "targets": [
    {
      "expr": "kube_rollout_status_phase{namespace='online-boutique'}",
      "legendFormat": "{{rollout}} — {{phase}}"
    }
  ]
},
{
  "title": "Active vs Preview Pod Count",
  "type": "timeseries",
  "targets": [
    {
      "expr": "kube_replicaset_status_ready_replicas{namespace='online-boutique'} * on(replicaset) group_left(rollout) label_replace(kube_rollout_info, 'replicaset', '$1', 'stable_replica_set', '(.*)')",
      "legendFormat": "{{rollout}} Blue"
    },
    {
      "expr": "kube_replicaset_status_ready_replicas{namespace='online-boutique'} * on(replicaset) group_left(rollout) label_replace(kube_rollout_info, 'replicaset', '$1', 'canary_replica_set', '(.*)')",
      "legendFormat": "{{rollout}} Green"
    }
  ]
}
```

### 4.3 — Thêm Alert Rule

**File mới:** `observability/kube-prometheus-stack/alerts/rollout-health.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: rollout-health
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: argo-rollouts
      rules:
        # Alert khi Rollout ở trạng thái Degraded
        - alert: RolloutDegraded
          expr: |
            kube_rollout_status_phase{
              namespace="online-boutique",
              phase="Degraded"
            } == 1
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Rollout {{ $labels.rollout }} đang Degraded"
            description: "Green environment của {{ $labels.rollout }} không healthy sau 2 phút. Cần abort hoặc investigate."

        # Alert khi Rollout bị Paused quá lâu (chờ approve)
        - alert: RolloutPausedTooLong
          expr: |
            kube_rollout_status_phase{
              namespace="online-boutique",
              phase="Paused"
            } == 1
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "Rollout {{ $labels.rollout }} đang Paused > 30 phút"
            description: "Có thể đã quên approve promotion cho {{ $labels.rollout }}."
```

### 4.4 — Chiến lược Rollback

#### Rollback tức thì (trong window 5 phút sau promote)

```bash
# Blue ReplicaSet vẫn còn chạy → rollback về Blue ngay lập tức
kubectl argo rollouts undo frontend -n online-boutique

# Hoặc từng bước: abort trước nếu đang trong quá trình promote
kubectl argo rollouts abort frontend -n online-boutique
kubectl argo rollouts undo frontend -n online-boutique
```

#### Rollback sau khi Blue đã scale down (sau 5 phút)

Lúc này không còn Blue ReplicaSet. Rollback bằng cách revert image tag trong Git:

```bash
# 1. Tìm image tag của phiên bản cũ
git log --oneline platform/gitops/kustomize/applications/online-boutique/frontend/rollout.yaml

# 2. Revert commit
git revert <commit-hash>
git push origin main

# 3. ArgoCD sẽ tự sync → Argo Rollouts tạo một chu kỳ Blue-Green mới
#    với image cũ. Green (= version cũ) healthy → promote về stable.
```

#### Bảng tóm tắt các lệnh quan trọng

| Tình huống | Lệnh |
|---|---|
| Xem status tất cả rollout | `kubectl argo rollouts list rollouts -n online-boutique` |
| Xem chi tiết một rollout | `kubectl argo rollouts get rollout frontend -n online-boutique --watch` |
| Promote Green → Active | `kubectl argo rollouts promote frontend -n online-boutique` |
| Abort (hủy deploy hiện tại) | `kubectl argo rollouts abort frontend -n online-boutique` |
| Rollback về phiên bản trước | `kubectl argo rollouts undo frontend -n online-boutique` |
| Restart rollout | `kubectl argo rollouts restart frontend -n online-boutique` |

---

## 7. Thứ tự migrate các service

### Lý do cần migrate từng nhóm, không migrate tất cả cùng lúc

Nếu migrate tất cả 10 service cùng một lúc và có vấn đề, rất khó isolate nguyên nhân. Migrate từng đợt giúp kiểm soát rủi ro và xác nhận từng service hoạt động đúng trước khi chuyển sang service tiếp theo.

### Đợt 1 — Frontend + 2 service business-critical (Tuần 2)

```
frontend → checkoutservice → cartservice
```

**Lý do ưu tiên:**
- `frontend` là entry point duy nhất từ internet, dễ test nhất bằng HTTP
- `checkoutservice` và `cartservice` là 2 service quan trọng nhất về business
- Cả 3 đều đã có HPA trong prod → cần update HPA cùng lúc

**Quy trình cho từng service trong đợt 1:**
1. Tạo `rollout.yaml` (copy từ `deployment.yaml`, đổi apiVersion/kind/strategy)
2. Tạo `service-active.yaml` và `service-preview.yaml`
3. Update `kustomization.yaml` của service
4. Update `ingress.yaml` (chỉ với frontend)
5. Update HPA trong `overlays/prod/hpa.yaml`
6. Update patch targets trong `overlays/dev/kustomization.yaml` và `overlays/prod/kustomization.yaml`
7. Commit, push, chờ ArgoCD sync
8. Verify: `kubectl argo rollouts get rollout frontend -n online-boutique`
9. Test smoke trên preview URL
10. Promote (hoặc chờ auto-promote ở dev)

### Đợt 2 — 3 service catalog/currency (Tuần 3 đầu)

```
productcatalogservice → currencyservice → paymentservice
```

### Đợt 3 — 4 service còn lại (Tuần 3 cuối)

```
shippingservice → emailservice → recommendationservice → adservice
```

> `loadgenerator` không cần migrate — đây là tool test, không phải service thực.

---

## 8. Bảng tóm tắt công việc

| Tuần | Giai đoạn | Việc cần làm | File thay đổi |
|---|---|---|---|
| 1 | Cài đặt platform | Tạo `argo-rollouts/kustomization.yaml` | `platform-services/argo-rollouts/kustomization.yaml` |
| 1 | Cài đặt platform | Thêm `argo-rollouts/` vào platform-services | `platform-services/kustomization.yaml` |
| 1 | Bảo mật | Thêm `argo-rollouts` namespace vào OPA exclusions | `security/opa-gatekeeper/constraints/*.yaml` |
| 1 | Verify | Kiểm tra controller chạy, CRD đã cài | (kubectl) |
| 2 | Migrate Đợt 1 | Tạo rollout.yaml cho frontend | `frontend/rollout.yaml` |
| 2 | Migrate Đợt 1 | Tạo service-active/preview cho frontend | `frontend/service-active.yaml`, `frontend/service-preview.yaml` |
| 2 | Migrate Đợt 1 | Cập nhật ingress trỏ vào frontend-active | `frontend/ingress.yaml` |
| 2 | Migrate Đợt 1 | Lặp lại cho checkoutservice, cartservice | `checkoutservice/`, `cartservice/` |
| 2 | Overlay | Cập nhật patch target sang `kind: Rollout` | `overlays/dev/kustomization.yaml`, `overlays/prod/kustomization.yaml` |
| 2 | Overlay | Tạo bluegreen-patch.yaml cho dev và prod | `overlays/dev/bluegreen-patch.yaml`, `overlays/prod/bluegreen-patch.yaml` |
| 2 | HPA | Cập nhật HPA scaleTargetRef | `overlays/prod/hpa.yaml` |
| 2-3 | CI/CD | Thêm step watch rollout status vào pipeline | (pipeline file) |
| 3 | Migrate Đợt 2-3 | Migrate 7 service còn lại | Tất cả service còn lại |
| 3 | Observability | Thêm panel Rollout status vào Grafana | `dashboards/application-metrics.yaml` |
| 3 | Observability | Tạo PrometheusRule cho Rollout alerts | `alerts/rollout-health.yaml` |
| 3 | Verify | End-to-end test toàn bộ flow | (manual test) |

---

*Tài liệu này được tạo dựa trên phân tích codebase `aws-eks-devsecops-platform` tại thời điểm tháng 6/2026.*
