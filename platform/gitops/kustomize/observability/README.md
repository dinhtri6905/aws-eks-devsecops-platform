# platform/gitops/kustomize/observability

Metrics, dashboards, and alerting for the cluster and for Online Boutique, delivered as a single `kube-prometheus-stack` Helm release plus a set of supporting Kustomize resources. Deployed as **Wave 3** in the ArgoCD App-of-Apps pipeline — after platform services and security, before the application — so that Prometheus and its ServiceMonitors are already running by the time Online Boutique pods start and need to be scraped.

---

## Directory Structure

```text
observability/
└── kube-prometheus-stack/
    ├── kustomization.yaml         # helmCharts block (chart v58.7.2) + all custom resources
    ├── values.yaml                 # Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics config
    │
    ├── dashboards/                 # Grafana dashboards as ConfigMaps (sidecar auto-load)
    │   ├── cluster-overview.yaml
    │   ├── node-metrics.yaml
    │   └── application-metrics.yaml
    │
    ├── alerts/                     # Custom PrometheusRule alert groups
    │   ├── cpu-usage.yaml
    │   ├── memory-usage.yaml
    │   └── pod-restarts.yaml
    │
    └── servicemonitors/            # Prometheus scrape target definitions
        ├── kubernetes.yaml
        └── online-boutique.yaml
```

---

## How It Works

The entire stack is installed by one Helm release (`kube-prometheus-stack`, chart version `58.7.2`, from `https://prometheus-community.github.io/helm-charts`) into the `monitoring` namespace, with all custom resources layered on top via plain Kustomize `resources`:

```text
helmCharts: kube-prometheus-stack
  → Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics
resources:
  → 3 Grafana dashboard ConfigMaps   (picked up by the Grafana sidecar)
  → 3 PrometheusRule alert groups    (picked up by the Prometheus Operator)
  → 2 ServiceMonitors                (picked up by the Prometheus Operator)
```

### Prometheus

Configured with `serviceMonitorSelectorNilUsesHelmValues: false` and `podMonitorSelectorNilUsesHelmValues: false`, so it discovers ServiceMonitors and PrometheusRules from **any** namespace rather than only ones matching the Helm release's own labels — this is what allows the `online-boutique` namespace's ServiceMonitor to be picked up automatically. Storage is a 10Gi `gp3` PersistentVolumeClaim with a 7-day retention window (`retentionSize: 8GB`), sized for development use rather than long-term retention.

### Grafana

The sidecar container watches for ConfigMaps labeled `grafana_dashboard: "1"` in the `monitoring` namespace and loads them automatically — no manual dashboard import is required. Persistence is a 5Gi `gp3` volume. The default admin password (`admin`) is set directly in `values.yaml` for dev; production environments are expected to override this via a secret rather than plaintext Helm values.

### Alertmanager

Configured with a `null` receiver for both the default route and the built-in `Watchdog` alert — meaning the custom alert rules below fire and are visible in the Alertmanager and Grafana UI, but are not yet wired to an external notification channel (e.g. Slack) at the Helm-values level.

### Node Exporter & kube-state-metrics

Both enabled to provide, respectively, per-node OS-level metrics and Kubernetes object-state metrics. `kubeControllerManager`, `kubeScheduler`, `kubeProxy`, and `kubeEtcd` are explicitly disabled, since EKS does not expose these control-plane components for scraping.

---

## Dashboards

| File | Dashboard | Scope |
|---|---|---|
| `cluster-overview.yaml` | Cluster Overview | Node count, running pods, cluster CPU/memory %, restarts |
| `node-metrics.yaml` | Node Metrics | Per-node CPU %, memory %, disk %, network Rx/Tx (sourced from node-exporter) |
| `application-metrics.yaml` | Application Metrics — Online Boutique | Running pods, restarts, per-service CPU/memory, restart trend, scoped to the `online-boutique` namespace |

---

## Alerting

Nine `PrometheusRule` alerts across three groups, each with a warning and a critical tier where applicable:

| Group | Alert | Condition | Severity |
|---|---|---|---|
| CPU | `NodeCPUHighWarning` | Node CPU > 80% for 5m | warning |
| CPU | `NodeCPUHighCritical` | Node CPU > 90% for 5m | critical |
| CPU | `ContainerCPUThrottling` | Container CPU throttling > 25% for 10m (online-boutique) | warning |
| Memory | `NodeMemoryHighWarning` | Node memory > 85% for 5m | warning |
| Memory | `NodeMemoryHighCritical` | Node memory > 95% for 5m | critical |
| Memory | `ContainerMemoryNearLimit` | Container memory > 90% of its limit for 5m (online-boutique) | warning |
| Pod restarts | `PodCrashLooping` | > 5 restarts in 1h (online-boutique) | warning |
| Pod restarts | `PodCrashLoopingCritical` | > 15 restarts in 1h (online-boutique) | critical |
| Pod restarts | `PodNotReady` | Pod not ready for 5m (online-boutique) | warning |

---

## Service Discovery

| ServiceMonitor | Targets | Notes |
|---|---|---|
| `kubernetes.yaml` | `kubelet` (node + cAdvisor metrics), `coredns` | EKS hides etcd, controller-manager, and scheduler, so they are not targeted |
| `online-boutique.yaml` | All Services in the `online-boutique` namespace | Uses an empty label selector to match every service, since Online Boutique services carry only an `app` label and no shared `project` label; scrapes both `grpc` and `http` named ports at `/metrics` |

---

## Useful Commands

```bash
# Port-forward Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

# Port-forward Prometheus
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090

# Check that Online Boutique targets are healthy
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.labels.namespace=="online-boutique") | {job: .labels.job, health: .health}'

# List active PrometheusRule alerts
kubectl get prometheusrules -n monitoring

# Check Grafana dashboard ConfigMaps are present
kubectl get configmap -n monitoring -l grafana_dashboard=1
```
