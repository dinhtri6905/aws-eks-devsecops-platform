- ArgoCD Application bị Terraform quản lý thay vì để GitOps tự trị — Root App nên chỉ bootstrap một lần (qua kubectl apply hoặc Terraform chạy đúng 1 lần rồi bỏ qua), sau đó để Git/ArgoCD tự cập nhật chính nó. Để Terraform tiếp tục quản lý sẽ xung đột với các field ArgoCD tự ghi đè (status, operation), gây drift giả.
- Blue/Green áp dụng cho toàn bộ 11 service thay vì chọn lọc theo rủi ro — chỉ nên dùng cho service quan trọng, traffic cao (frontend, checkout); các service phụ (email, currency...) dùng rolling update thường là đủ, tránh tốn gấp đôi resource không cần thiết.
- Thiếu NetworkPolicy — hiện tại pod nào cũng gọi được pod nào trong cluster; cần giới hạn traffic giữa các service theo nguyên tắc least privilege ở tầng network, không chỉ dừng ở admission control (Gatekeeper).
- SSO/RBAC để ở mục "tương lai" thay vì làm ngay — đang dùng admin password mặc định cho ArgoCD, đây là rủi ro bảo mật cần xử lý từ đầu, không nên để như một enhancement có thể trì hoãn.

1. Tách hẳn ArgoCD ra khỏi Terraform, dùng kubectl apply thủ công
Bước 1 — Tạo file platform/gitops/argocd/root-app.yaml chứa AppProject + Application
Bước 2 — Sửa modules/argocd-bootstrap/main.tf: xóa 2 resource kubernetes_manifest (cả argocd_project và argocd_root_app)
Bước 3 — Sửa modules/argocd-bootstrap/outputs.tf: xóa output liên quan
Bước 4 — Dọn variables.tf của module và environments/dev/main.tf/variables.tf: giữ lại biến vẫn cần (vd. cho secret repo SSH key), đánh dấu biến nào chỉ còn dùng để generate YAML tham khảo
Bước 5 — Trên cluster hiện tại của bạn: dọn state + dọn resource cũ trên cluster (vì bạn đã apply 2 resource này qua Terraform rồi — cần xử lý migration, không phải tạo mới từ đầu)
Bước 6 — Cập nhật Deployment Guide / README: thêm bước kubectl apply -f platform/gitops/argocd/root-app.yaml vào đúng vị trí trong quy trình


