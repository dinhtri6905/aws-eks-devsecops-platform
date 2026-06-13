Theo cấu trúc, root-app trỏ vào `argocd/applications/` (đã có 4 file), nhưng 4 Application đó lại trỏ vào các path trong `kustomize/` mà **chưa tồn tại** → sẽ gây `ComparisonError` ngay khi ArgoCD sync.

## Đề xuất lộ trình theo cấu trúc

| Bước | Thư mục | Vì sao trước |
|---|---|---|
| **1** | `kustomize/base/` | Namespace + common-labels dùng chung cho mọi overlay |
| **2** | `kustomize/platform-services/` (metrics-server, aws-lb-controller) | `platform-services.yaml` Application cần ngay, không phụ thuộc gì khác |
| **3** | `kustomize/security/` (opa-gatekeeper templates+constraints, falco) | Rego/Falco rules đã có sẵn ở `platform/security/`, giờ map sang Helm-values + kustomization |
| **4** | `kustomize/observability/kube-prometheus-stack/` | values + dashboards + alerts + servicemonitors |
| **5** | `kustomize/applications/online-boutique/` | 12 service dirs + kustomization — phần lớn công việc |
| **6** | `kustomize/overlays/dev/` và `overlays/prod/` | Patches cuối cùng, tham chiếu tới base + applications |

Vì `platform-services.yaml` (Application) hiện đang trỏ `overlays/dev` + `kustomize.components`, còn `online-boutique.yaml` cũng trỏ `overlays/dev` — nên **base + overlays/dev** là khung sườn bắt buộc phải có trước để mọi thứ build được.

## Tôi đề xuất thứ tự thực hiện thực tế

1. **`kustomize/base/`** (3 file nhỏ) — làm trước, nhanh
2. **`kustomize/platform-services/`** (metrics-server + aws-load-balancer-controller, mỗi cái 2-3 file)
3. **`kustomize/overlays/dev/`** khung cơ bản (kustomization.yaml trỏ tới base + platform-services, để Application #1 sync được ngay)
4. Tiếp tục **security**, **observability**, **online-boutique**, rồi hoàn thiện **overlays/dev** và thêm **overlays/prod**

Bạn muốn tôi bắt đầu **bước 1 (base/) + bước 2 (platform-services/)** ngay không? Đây là phần nhỏ và sẽ làm Application `platform-services` sync được sớm nhất.