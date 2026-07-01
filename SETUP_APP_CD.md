# Application CD Setup Guide

## 📋 Prerequisites

### 1. GitHub Secrets Configuration
App CD workflow requires 4 secrets in your GitHub repository. Set them up at:
`Settings → Secrets and variables → Actions → New repository secret`

#### Required Secrets:

**a) AWS_DEV_ROLE_ARN**
- **What**: IAM role ARN for OIDC-based ECR push authentication
- **Format**: `arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME`
- **How to get**:
  - Run: `aws iam list-roles --query "Roles[?contains(RoleName, 'github')].Arn" --output text`
  - Or check AWS Console: IAM → Roles → search for "github"
  - Usually from terraform-cd workflow setup
- **Example**: `arn:aws:iam::041659741748:role/eks-devsecops-github-actions-oidc`

**b) AWS_ACCOUNT_ID**
- **What**: 12-digit AWS account ID
- **How to get**: Run `aws sts get-caller-identity --query Account --output text`
- **Example**: `041659741748`

**c) SLACK_WEBHOOK_URL** (Optional)
- **What**: Slack incoming webhook for CD notifications
- **How to get**:
  - Go to Slack workspace → Create incoming webhook
  - URL format: `https://hooks.slack.com/services/T.../B.../...`
- **Leave empty** if Slack notifications not needed (workflow won't fail)

**d) GITOPS_BOT_TOKEN**
- **What**: GitHub Personal Access Token with `repo` (full control of private repos) scope
- **How to create**:
  1. GitHub Profile → Settings → Developer settings → Personal access tokens → Tokens (classic)
  2. Generate new token
  3. Scopes: Check `repo` (all sub-permissions)
  4. Copy token immediately (won't show again)
- **Purpose**: Allows GitHub Actions to commit rendered GitOps values back to Git
- **Note**: This token will be stored in Actions secrets, use a bot/service account if possible

## 🚀 Complete Deployment Flow

### Phase 1: Infrastructure Setup (Terraform CD)
```
terraform apply → renders AWS values → commits to Git
                      ↓
            Terraform outputs created:
            - vpc_id
            - cluster_name
            - aws_region
```

**Status**: ✅ Already configured in `.github/workflows/terraform-cd.yaml`

---

### Phase 2: Application Build & Push (App CD)
```
Manual trigger: workflow_dispatch
    ↓
detect-changes → identifies modified services
    ↓
build-and-scan (parallel per service)
  ├── Build Docker image
  ├── Trivy vulnerability scan
  ├── Block if CRITICAL CVEs found
  └── Push to ECR: {AWS_ACCOUNT_ID}.dkr.ecr.{region}.amazonaws.com/eks-devsecops-dev-{service}:{git-sha}
    ↓
update-gitops
  ├── Update Kustomize image tags
  ├── Commit to Git (via GITOPS_BOT_TOKEN)
  └── ArgoCD detects change automatically
```

**Status**: ✅ Configured, awaiting GitHub secrets

---

### Phase 3: GitOps Sync (ArgoCD)
```
Git change detected
    ↓
ArgoCD Application (platform-services, security, observability, applications)
    ↓
Kubernetes cluster receives manifests
    ↓
Pods pull new images and start
```

**Status**: ✅ ArgoCD already deployed via terraform-cd

---

## 📁 Directory Structure

```
platform/gitops/kustomize/
├── base/                           # Not used in app CD
├── applications/online-boutique/   # Base for all 13 microservices
│   └── kustomization.yaml          # Lists all service deployments
├── overlays/dev/                   # Dev environment overlay
│   ├── kustomization.yaml          # Points to ./applications/online-boutique
│   └── applications/online-boutique/
│       ├── kustomization.yaml      # Dev-specific patches & image generation
│       ├── replicas-patch.yaml     # 1 replica per service for dev
│       └── configmap-patch.yaml    # Dev environment config
└── [platform-services, security, observability]/
    └── (deployed separately by ArgoCD platform Application)
```

**Key Point**: `overlays/dev/applications/online-boutique/kustomization.yaml` is where app-cd updates image tags via:
```bash
kustomize edit set image servicename={ECR_REGISTRY}/{PROJECT_NAME}-dev-{servicename}:{TAG}
```

---

## 🔧 Testing & Validation

### Step 1: Verify App CI Passes
1. Go to GitHub Actions
2. Look for **Application CI** workflow run
3. Ensure all jobs pass: ✅ gitleaks, ✅ kustomize-validate, ✅ opa-k8s-policies, ✅ falco-validate, ✅ trivy-filesystem, ✅ app-ci-summary

**Current Status**: Workflow should now pass after kustomization fixes

### Step 2: Verify GitHub Secrets
1. Go to repository Settings → Secrets and variables → Actions
2. Confirm all 4 secrets are present:
   - ✓ AWS_DEV_ROLE_ARN
   - ✓ AWS_ACCOUNT_ID
   - ✓ SLACK_WEBHOOK_URL (optional)
   - ✓ GITOPS_BOT_TOKEN

### Step 3: Trigger App CD Workflow
1. Go to GitHub Actions → Application CD
2. Click "Run workflow"
3. Select "dev" environment
4. (Optional) Specify service name, or leave empty for auto-detect
5. Watch workflow progress:
   - detect-changes: Identifies changed services
   - build-and-scan: Builds & pushes images
   - update-gitops: Commits to Git
   - Slack notification (if webhook configured)

### Step 4: Verify ArgoCD Sync
1. Port-forward to ArgoCD:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
2. Go to https://localhost:8080
3. Login (credentials from: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`)
4. Check **applications** Application → should show "Synced" status
5. Verify pods are running:
   ```bash
   kubectl get pods -n online-boutique
   ```

---

## 🐛 Troubleshooting

### App CD Workflow Fails: "Unable to resolve action"
- **Cause**: GitHub Actions workflow syntax error or missing secrets
- **Fix**: Check if all secrets are created, re-run workflow

### Image Tag Not Updated in Kustomize
- **Cause**: Service not detected in changed files, or Dockerfile not found
- **Check**: 
  ```bash
  git diff HEAD^1...HEAD -- microservices-application/
  # Should show your changed service
  ls microservices-application/{service}/Dockerfile
  # Should exist
  ```

### CRITICAL Vulnerabilities Block Push
- **Cause**: Trivy detected CRITICAL CVEs in container image
- **Fix**: Update base image, fix vulnerable packages, rebuild
- **Logs**: Check "Print human-readable table" step in GitHub Actions

### ArgoCD Not Syncing
- **Cause**: Git commit with new image tag not pushed, or ArgoCD repo URL mismatch
- **Check**:
  ```bash
  git log --oneline -5
  # Should show recent "chore(gitops): update image tags..." commit
  
  kubectl describe application applications -n argocd
  # Should show "Repo: https://github.com/..."
  ```

---

## 📚 Files Modified/Created

**Modified**:
- `.github/workflows/app-ci.yaml` - Fixed kustomize paths and trivy-action version
- `.github/workflows/terraform-cd.yaml` - Added rendering and git commit steps
- `platform/gitops/kustomize/platform-services/aws-load-balancer-controller/kustomization.yaml`
- `platform/gitops/kustomize/security/falco/kustomization.yaml`
- `platform/gitops/kustomize/overlays/dev/kustomization.yaml`

**Created**:
- `platform/gitops/kustomize/observability/kustomization.yaml`
- `platform/gitops/kustomize/overlays/dev/applications/online-boutique/kustomization.yaml`
- `platform/gitops/kustomize/overlays/dev/applications/online-boutique/replicas-patch.yaml`
- `platform/gitops/kustomize/overlays/dev/applications/online-boutique/configmap-patch.yaml`
- `platform/gitops/scripts/Render-LbcValues.ps1`

---

## ✅ Next Steps

1. **Create GitHub Secrets** (1-2 minutes)
   - Set AWS_DEV_ROLE_ARN
   - Set AWS_ACCOUNT_ID
   - (Optional) Set SLACK_WEBHOOK_URL
   - Set GITOPS_BOT_TOKEN

2. **Verify App CI Workflow** (check if it passes)
   - GitHub Actions → Application CI
   - All jobs should show ✅

3. **Trigger App CD Workflow** (manual dispatch)
   - GitHub Actions → Application CD → Run workflow
   - Verify build & push success

4. **Monitor ArgoCD Sync**
   - kubectl get pods -n online-boutique
   - Verify all 13 services are Running

---

## 🔐 Security Notes

- **GITOPS_BOT_TOKEN**: Never commit this token. It's stored securely in GitHub Actions secrets.
- **AWS_DEV_ROLE_ARN**: Follows OIDC best practice (no long-lived credentials)
- **Network**: All commits use HTTPS via GitHub's OAuth token
- **Least Privilege**: App CD only has access to:
  - ECR push for dev account
  - Git push to main branch
  - Slack notifications (if configured)

