# Runbook: Kết nối kubectl & ArgoCD vào EKS Cluster

## Bối cảnh

Cluster EKS được provision bởi Terraform, chạy qua GitHub Actions với OIDC role
(`github-actions-terraform-dev`). EKS chỉ tự động cấp quyền truy cập cho
identity đã tạo cluster — **identity cá nhân của kỹ sư vận hành không tự động
có quyền**, dù `aws eks update-kubeconfig` chạy thành công. Đây là nguyên nhân
phổ biến gây lỗi:

```
error: You must be logged in to the server (the server has asked for the client to provide credentials)
```

---

## Quy trình

### Bước 1 — Xác nhận identity AWS hiện tại

```powershell
aws sts get-caller-identity
```

Ghi nhớ `Arn` trả về — đây là identity sẽ cần được cấp quyền vào cluster.

### Bước 2 — Cập nhật kubeconfig trỏ tới đúng cluster

```powershell
aws eks update-kubeconfig --region <AWS_REGION> --name <CLUSTER_NAME>
```

Bước này **luôn thành công** vì chỉ ghi file cấu hình cục bộ, không kiểm tra
quyền truy cập.

### Bước 3 — Kiểm tra identity đã có quyền vào cluster chưa

```powershell
aws eks list-access-entries --cluster-name <CLUSTER_NAME> --region <AWS_REGION>
```

Nếu ARN của bạn (Bước 1) **không nằm trong danh sách** → đây là nguyên nhân
gốc gây lỗi ở trên.

### Bước 4 — Cấp quyền cho identity của bạn (nếu chưa có)

```powershell
aws eks create-access-entry `
  --cluster-name <CLUSTER_NAME> `
  --region <AWS_REGION> `
  --principal-arn <YOUR_IAM_ARN> `
  --type STANDARD

aws eks associate-access-policy `
  --cluster-name <CLUSTER_NAME> `
  --region <AWS_REGION> `
  --principal-arn <YOUR_IAM_ARN> `
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster
```

> ⚠️ Phải chạy bằng một identity **đã có quyền** cấp EKS access (ví dụ role
> Terraform, hoặc IAM admin). Nếu chính identity của bạn chưa có quyền
> `eks:CreateAccessEntry` / `eks:AssociateAccessPolicy` thì lệnh sẽ báo
> `AccessDenied` — cần nhờ một identity khác chạy hộ.

### Bước 5 — Xác nhận đã kết nối được

```powershell
kubectl get nodes
```

Ra danh sách node là coi như xong phần kết nối cluster.

### Bước 6 — Truy cập ArgoCD (chỉ làm sau khi Bước 5 OK)

```powershell
# Lấy password admin (base64-encoded)
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}"

# Decode base64 (PowerShell)
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("<chuỗi-vừa-lấy>"))

# Mở kết nối tới ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Mở trình duyệt tới `https://localhost:8080`, đăng nhập `admin` / password vừa
decode.

### Bước 7 (khuyến nghị lâu dài) — Đưa access entry vào Terraform

Không nên để access entry sống ngoài Terraform (tạo tay qua CLI ở Bước 4) vì:

- Lần `terraform apply` / `destroy` sau có thể vô tình xoá mất nếu module EKS
  quản lý access entries dạng declarative (Terraform so sánh state với thực
  tế, thấy entry "lạ" không khai báo trong code → xoá).
- Không ai khác trong team biết identity này đã được cấp quyền, gây khó bảo
  trì và khó audit.

→ Thêm identity vào biến kiểu `access_entries` (hoặc tương đương) trong
module Terraform `eks`, commit vào repo, rồi `terraform apply` lại — để quyền
này được quản lý như code, nhất quán với cách cluster được provision.

---

## Tóm tắt

`aws eks update-kubeconfig` chỉ tạo file cấu hình, **không cấp quyền gì cả**.
Quyền thật sự nằm ở **EKS Access Entries**. Ai tạo cluster (ở đây là role
Terraform CI/CD) không tự động cấp quyền cho identity cá nhân của kỹ sư vận
hành, nên phải cấp thủ công (Bước 4) hoặc qua Terraform (Bước 7) trước khi
`kubectl` / ArgoCD hoạt động được.
