Thứ tự destroy chuẩn
Bước 1 — Xóa ArgoCD Applications (để ArgoCD tự dọn K8s resources)
powershell# Xóa Root Application — ArgoCD sẽ cascade delete toàn bộ child apps
# và mọi resource K8s chúng quản lý (Deployments, Services, Ingress...)
kubectl delete application eks-devsecops-dev-root -n argocd

# Đợi cho đến khi tất cả child applications biến mất
kubectl get applications -n argocd --watch
Đợi cho đến khi không còn application nào — có thể mất 3–5 phút vì ArgoCD phải cascade delete từng resource theo resources-finalizer.argocd.argoproj.io.
powershell# Xác nhận các namespace workload đã sạch
kubectl get pods -n online-boutique
kubectl get pods -n monitoring
kubectl get pods -n gatekeeper-system
kubectl get pods -n falco
Bước 2 — Xóa AppProject
powershellkubectl delete appproject platform-project -n argocd
Bước 3 — Xóa các LoadBalancer trước khi destroy Terraform
AWS ALB được tạo bởi AWS Load Balancer Controller (K8s), không phải Terraform — nếu destroy Terraform ngay, VPC sẽ không xóa được vì còn ENI của ALB treo lại.
powershell# Kiểm tra còn Ingress nào không
kubectl get ingress -A

# Xóa hết nếu còn sót
kubectl delete ingress --all -n online-boutique
Đợi ALB biến mất trên AWS Console (EC2 → Load Balancers) trước khi qua bước tiếp theo — thường mất 1–2 phút.
Bước 4 — Xóa ArgoCD khỏi Terraform state và uninstall
powershellcd platform/infrastructure/terraform/environments/dev

# Gỡ ArgoCD resources khỏi state trước (nếu còn)
terraform state rm "module.argocd-bootstrap.kubernetes_manifest.argocd_root_app" 2>$null
terraform state rm "module.argocd-bootstrap.kubernetes_manifest.argocd_project" 2>$null
Bước 5 — Terraform destroy toàn bộ infrastructure
Option A — GitHub Actions (nếu pipeline còn hoạt động):
Trigger terraform-cd.yaml manually với action: destroy — pipeline sẽ yêu cầu approval từ 2 reviewers (vì dev-destroy environment được bảo vệ).
Option B — Manual:
powershellcd platform/infrastructure/terraform/environments/dev

terraform destroy
Gõ yes khi được hỏi. Quá trình này mất khoảng 15–20 phút, thứ tự destroy Terraform tự tính toán nhưng thường là:
EKS Node Group → EKS Addons → EKS Cluster
→ RDS → ECR → ALB resources
→ NAT Gateway → Subnets → VPC
→ IAM Roles → CloudWatch Log Groups
→ Security Groups
Bước 6 — Xóa Terraform Backend (tuỳ chọn)
Nếu muốn xóa luôn S3 bucket và DynamoDB lock table (được tạo bởi bootstrap module, không nằm trong environments/dev state):
powershellcd platform/infrastructure/terraform/bootstrap
terraform destroy

Cảnh báo: Bước này xóa hoàn toàn Terraform state — không thể recover. Chỉ chạy khi chắc chắn đã destroy xong toàn bộ resources ở Bước 5.


Checklist xác nhận đã xóa sạch
Sau khi destroy xong, kiểm tra trên AWS Console:
powershell# 1. Không còn EKS cluster
aws eks list-clusters --region ap-southeast-1

# 2. Không còn RDS instance
aws rds describe-db-instances --region ap-southeast-1 --query 'DBInstances[*].DBInstanceIdentifier'

# 3. Không còn NAT Gateway (tốn tiền nhất nếu bị sót)
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter Name=state,Values=available --query 'NatGateways[*].NatGatewayId'

# 4. Không còn Load Balancer
aws elbv2 describe-load-balancers --region ap-southeast-1 --query 'LoadBalancers[*].LoadBalancerName'

# 5. Không còn ECR repositories (nếu muốn xóa luôn images)
aws ecr describe-repositories --region ap-southeast-1 --query 'repositories[*].repositoryName'
Các resource hay bị sót nhất và tốn tiền là NAT Gateway, ALB, và RDS — kiểm tra kỹ 3 thứ này trước.