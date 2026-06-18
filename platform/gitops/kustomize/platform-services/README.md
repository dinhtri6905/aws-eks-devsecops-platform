# platform/gitops/kustomize/platform-services

Foundational cluster add-ons that other platform layers depend on. Deployed as **Wave 1** in the ArgoCD App-of-Apps pipeline — before security, observability, and the application — since both Gatekeeper's admission flow and the application's HPA/Ingress resources depend on what this layer installs.

---

## Directory Structure

```text
platform-services/
├── kustomization.yaml                      # Aggregator — references both subcomponents
│
├── metrics-server/
│   ├── kustomization.yaml                  # helmCharts block (chart v3.12.2)
│   └── values.yaml                         # Resource limits, security context, kubelet args
│
└── aws-load-balancer-controller/
    ├── kustomization.yaml                  # helmCharts block (chart v1.8.1) + ingressclass.yaml
    ├── values.yaml                         # IRSA role annotation, cluster name, region
    └── ingressclass.yaml                   # IngressClass "alb" — default for the cluster
```

---

## metrics-server

Installed via Helm chart `metrics-server` v3.12.2 from `https://kubernetes-sigs.github.io/metrics-server/`, into the `kube-system` namespace.

Provides the metrics pipeline used by `kubectl top` and by the prod-overlay HorizontalPodAutoscaler resources. Key configuration in `values.yaml`:

| Setting | Value | Reason |
|---|---|---|
| `args: --kubelet-insecure-tls` | enabled | EKS managed-node kubelet certificates are not signed for the internal IP by default |
| `args: --kubelet-preferred-address-types` | `InternalIP` | Matches EKS node networking (VPC CNI) |
| `securityContext` | non-root, read-only root filesystem, all capabilities dropped | Aligns with the OPA Gatekeeper constraints enforced cluster-wide |
| `resources` | 50m/64Mi request, 200m/256Mi limit | Sized for a small add-on, not a high-throughput service |

---

## aws-load-balancer-controller

Installed via Helm chart `aws-load-balancer-controller` v1.8.1 from `https://aws.github.io/eks-charts`, into the `kube-system` namespace. Watches `Ingress` and `Service` resources cluster-wide and provisions the corresponding AWS ALB/NLB.

### IAM Dependency

The controller authenticates to the AWS API via IRSA. The service account annotation in `values.yaml` references the IAM role ARN produced by the Terraform `eks` module output (`alb_controller_role_arn`):

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::<ACCOUNT_ID>:role/eks-devsecops-dev-alb-controller-role"
```

`clusterName`, `region`, and `vpcId` are also required by the chart; `vpcId` is intentionally left blank in the base `values.yaml` and is expected to be supplied through an environment-specific override, since hardcoding infrastructure-derived values into GitOps breaks the separation between what Terraform owns and what Git owns.

### IngressClass

`ingressclass.yaml` declares the cluster's `alb` IngressClass and marks it as the default (`ingressclass.kubernetes.io/is-default-class: "true"`). This is what Online Boutique's `frontend` Ingress (`spec.ingressClassName: alb`) resolves against — without it, the AWS Load Balancer Controller has nothing telling it which Ingress resources to manage.

### Security Posture

`values.yaml` sets `runAsNonRoot`, `readOnlyRootFilesystem: true`, and drops all Linux capabilities — the same baseline enforced on application workloads by the OPA Gatekeeper constraints in `security/`.

---

## Sync Behavior

Both subcomponents are referenced from the top-level `kustomization.yaml`:

```yaml
resources:
  - metrics-server/
  - aws-load-balancer-controller/
```

ArgoCD applies this layer first (sync-wave "1") so that by the time Gatekeeper (wave 2) starts enforcing admission policy and Online Boutique (wave 4) starts requesting Ingress and HPA resources, the controllers that fulfil them are already running.
