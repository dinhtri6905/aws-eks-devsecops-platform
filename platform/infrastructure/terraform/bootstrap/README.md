# Backend Bootstrap

Module Terraform độc lập dùng để **khởi tạo một lần** toàn bộ hạ tầng lưu trữ Terraform remote state: S3 bucket với KMS encryption và DynamoDB table cho state locking.

---

## Mục đích

Trước khi các môi trường (`dev`, `prod`) có thể dùng S3 remote backend, cần tạo S3 bucket và DynamoDB table trước. Module `backend/` giải quyết vấn đề chicken-and-egg này bằng cách dùng **local state** để tạo các tài nguyên backend.

```
[Bước 1] Chạy backend/ với local state
    → Tạo S3 bucket + DynamoDB table

[Bước 2] Các environment (dev, prod) dùng S3 backend
    → Lưu state vào S3 bucket vừa tạo
```

---

## Tài nguyên được tạo

| Resource | Mô tả |
|----------|-------|
| `aws_kms_key` | KMS Customer Managed Key để mã hóa Terraform state |
| `aws_kms_alias` | Alias `alias/terraform-state` cho KMS key |
| `aws_s3_bucket` | S3 bucket lưu state, `prevent_destroy = true` |
| `aws_s3_bucket_versioning` | Versioning enabled — để rollback state |
| `aws_s3_bucket_server_side_encryption_configuration` | Mã hóa bằng KMS CMK |
| `aws_s3_bucket_public_access_block` | Block toàn bộ public access |
| `aws_dynamodb_table` | DynamoDB table `terraform-state-lock` cho state locking |

---

## Cấu hình bảo mật

| Thuộc tính | Giá trị |
|-----------|---------|
| S3 encryption | `aws:kms` với Customer Managed Key |
| KMS key rotation | `enable_key_rotation = true` (tự động rotate hàng năm) |
| S3 versioning | `Enabled` |
| S3 public access | Block tất cả 4 settings |
| DynamoDB billing | `PAY_PER_REQUEST` — không cần provision capacity |
| S3 lifecycle | `prevent_destroy = true` — không thể xóa nhầm |

---

## Variables

| Tên | Kiểu | Mô tả |
|-----|------|-------|
| `tfstate_bucket_name` | `string` | Tên S3 bucket (phải unique toàn cầu) |

---

## Outputs

| Tên | Mô tả |
|-----|-------|
| `tfstate_bucket_name` | Tên bucket — dùng cấu hình `backend.tf` trong environments |
| `tfstate_bucket_arn` | ARN bucket |
| `kms_key_arn` | ARN KMS key — dùng cấu hình `backend.tf` nếu muốn specify key |
| `dynamodb_table_name` | Tên DynamoDB table (mặc định: `terraform-state-lock`) |

---

## Cách chạy

> Chỉ chạy **một lần** khi khởi tạo project lần đầu.

```bash
cd backend/

# Không cần backend.tf — dùng local state
terraform init

# Xem trước
terraform plan -var="tfstate_bucket_name=three-tier-tfstate-2026" 

# Tạo hạ tầng backend
terraform apply -var="tfstate_bucket_name=three-tier-tfstate-2026"
```

Sau khi apply xong, copy tên bucket vào GitHub Secret `BUCKET_TF_STATE` và cập nhật `environments/dev/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "three-tier-tfstate-2026"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

---

## Cấu trúc file

```
backend/
├── bootstrap.tf          # Tài nguyên KMS, S3, DynamoDB
├── variables.tf          # Biến tfstate_bucket_name
├── outputs.tf            # Outputs
├── providers.tf          # AWS provider
└── versions.tf           # Terraform và provider version
```

---

## Lưu ý

- **Local state**: Module này dùng local state (không có `backend.tf`). State file được lưu trong thư mục `backend/terraform.tfstate` — **commit file này lên git hoặc backup riêng**.
- **`prevent_destroy = true`**: S3 bucket có lifecycle prevent_destroy — Terraform sẽ báo lỗi nếu cố destroy. Phải xóa lifecycle block trước.
- **Chạy một lần**: Không cần chạy lại trừ khi xóa bucket hoặc tạo môi trường mới cần bucket riêng.
- **KMS key deletion**: KMS key có `deletion_window_in_days = 7` — sau khi schedule delete, còn 7 ngày để hủy nếu cần.
