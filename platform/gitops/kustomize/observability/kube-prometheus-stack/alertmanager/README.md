### Dùng Kubernetes Secret để lưu trữ Slack Webhook

1. Lệnh tạo Secret thủ công
```bash
kubectl create secret generic slack-webhook-secret \
  --namespace monitoring \
  --from-literal=url='https://hooks.slack.com/services/T000/B000/XXXXXXXXXXXXXXXX' \
  --dry-run=client -o yaml | kubectl apply -f -
```
Thay URL bằng Incoming Webhook(Slack App → Incoming Webhooks → Add New Webhook to Workspace).

