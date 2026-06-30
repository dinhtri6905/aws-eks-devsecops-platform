# Destroy Guide - AWS EKS DevSecOps Platform

> **Objective:** Safely destroy the entire infrastructure while preventing orphaned resources (especially ALBs, ENIs, and NAT Gateways) from causing Terraform failures or unnecessary AWS charges.

---

# Prerequisites

Before starting, ensure that:

- You have backed up any required data.
- No critical workloads are running on the cluster.
- AWS CLI is authenticated.
- `kubectl` is configured to access the correct EKS cluster.
- You are working in the correct Terraform environment (`dev`).

---

# Step 1 - Delete ArgoCD Applications

Delete the **Root Application** so ArgoCD can automatically cascade delete all child applications and Kubernetes resources it manages.

```powershell
kubectl delete application eks-devsecops-dev-root -n argocd
```

Monitor the deletion process:

```powershell
kubectl get applications -n argocd --watch
```

Wait until **no Applications remain**.

> **Note:** This process typically takes **3–5 minutes** because ArgoCD removes resources through `resources-finalizer.argocd.argoproj.io`.

Verify that workload namespaces are empty:

```powershell
kubectl get pods -n online-boutique
kubectl get pods -n monitoring
kubectl get pods -n gatekeeper-system
kubectl get pods -n falco
```

Expected output:

```text
No resources found
```

---

# Step 2 - Delete the ArgoCD AppProject

After all Applications have been removed:

```powershell
kubectl delete appproject platform-project -n argocd
```

---

# Step 3 - Delete Remaining Load Balancers

AWS Load Balancer Controller creates **Application Load Balancers (ALBs)** from Kubernetes Ingress resources.

If Terraform is destroyed before the ALBs are removed, their attached ENIs may prevent the VPC from being deleted.

Check for remaining Ingress resources:

```powershell
kubectl get ingress -A
```

If any still exist:

```powershell
kubectl delete ingress --all -n online-boutique
```

Optionally verify that no `LoadBalancer` Services remain:

```powershell
kubectl get svc -A
```

Wait approximately **1–2 minutes** for AWS to delete the ALB.

Confirm in the AWS Console:

```
EC2
└── Load Balancers
```

Proceed only after all ALBs have disappeared.

---

# Step 4 - Remove ArgoCD Resources from Terraform State

Navigate to the Terraform environment:

```powershell
cd .\platform\infrastructure\terraform\environments\dev
```

List the current Terraform state:

```powershell
terraform state list
```

If the following resources still exist in the state, remove them:

```powershell
terraform state rm module.argocd-bootstrap.kubernetes_manifest.argocd_root_app
```

```powershell
terraform state rm module.argocd-bootstrap.kubernetes_manifest.argocd_project
```

> **Note**
>
> These commands remove resources **only from the Terraform state**. They do **not** delete Kubernetes resources.

---

# Step 5 - Destroy Infrastructure

## Option A - GitHub Actions (Recommended)

Trigger the GitHub Actions workflow:

```
terraform-cd.yaml
```

Choose:

```
destroy
```

If the `dev-destroy` environment is protected, the workflow will require approval from two reviewers.

---

## Option B - Manual

Navigate to the Terraform environment:

```powershell
cd .\platform\infrastructure\terraform\environments\dev
```

(Optional) Verify the current workspace:

```powershell
terraform workspace show
```

(Optional) Review the destroy plan:

```powershell
terraform plan -destroy
```

Destroy the infrastructure:

```powershell
terraform destroy
```

Or skip the confirmation prompt:

```powershell
terraform destroy -auto-approve
```

The destroy process usually takes **15–20 minutes**.

Terraform automatically destroys resources according to dependency order, typically:

```text
EKS Node Groups
        ↓
EKS Add-ons
        ↓
EKS Cluster
        ↓
RDS
        ↓
ECR
        ↓
ALB Resources
        ↓
NAT Gateway
        ↓
Subnets
        ↓
VPC
        ↓
IAM Roles
        ↓
CloudWatch Log Groups
        ↓
Security Groups
```

---

# Step 6 - Destroy Terraform Backend (Optional)

> **Perform this step only if you want to remove the Terraform backend completely.**

Navigate to the bootstrap directory:

```powershell
cd ..\..\bootstrap
```

(Optional) Review the destroy plan:

```powershell
terraform plan -destroy
```

Destroy the backend:

```powershell
terraform destroy
```

> ⚠️ **Warning**
>
> This permanently deletes:
>
> - Terraform State S3 Bucket
> - DynamoDB Lock Table
>
> After completion, the Terraform state cannot be recovered.
>
> Only perform this step after **Step 5** has completed successfully.

---

# Post-Destroy Verification

Run the following commands to verify that all AWS resources have been removed.

## 1. Verify EKS Clusters

```powershell
aws eks list-clusters --region ap-southeast-1
```

Expected output:

```text
[]
```

---

## 2. Verify RDS Instances

```powershell
aws rds describe-db-instances `
    --region ap-southeast-1 `
    --query "DBInstances[*].DBInstanceIdentifier"
```

---

## 3. Verify NAT Gateways

```powershell
aws ec2 describe-nat-gateways `
    --region ap-southeast-1 `
    --filter Name=state,Values=available `
    --query "NatGateways[*].NatGatewayId"
```

---

## 4. Verify Load Balancers

```powershell
aws elbv2 describe-load-balancers `
    --region ap-southeast-1 `
    --query "LoadBalancers[*].LoadBalancerName"
```

---

## 5. Verify ECR Repositories

```powershell
aws ecr describe-repositories `
    --region ap-southeast-1 `
    --query "repositories[*].repositoryName"
```

---

# Final Checklist

Verify that the following resources no longer exist:

- [ ] ArgoCD Applications
- [ ] ArgoCD AppProject
- [ ] Kubernetes Workloads
- [ ] Kubernetes Ingresses
- [ ] Application Load Balancers
- [ ] EKS Cluster
- [ ] EKS Node Groups
- [ ] RDS Instances
- [ ] NAT Gateways
- [ ] Security Groups
- [ ] VPC
- [ ] ECR Repositories (optional)
- [ ] CloudWatch Log Groups (if managed by Terraform)

---

# Common Resources Left Behind

These resources are the most common causes of failed destroys or unexpected AWS charges:

| Resource | Impact |
|----------|--------|
| NAT Gateway | Continues incurring hourly charges if left behind |
| Application Load Balancer (ALB) | Retains ENIs that prevent VPC deletion |
| RDS Instance | Continues incurring storage and compute charges |

> **Always verify that NAT Gateways, ALBs, and RDS instances have been successfully deleted before considering the destroy process complete.**