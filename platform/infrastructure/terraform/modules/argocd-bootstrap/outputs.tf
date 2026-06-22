output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_release_name" {
  description = "Helm release name of the ArgoCD installation"
  value       = helm_release.argocd.name
}

output "argocd_chart_version" {
  description = "Helm chart version of ArgoCD that was deployed"
  value       = helm_release.argocd.version
}

output "argocd_server_service" {
  description = "Kubernetes Service name of the ArgoCD server (use with kubectl port-forward)"
  value       = "argocd-server"
}

output "gitops_repo_url" {
  description = "GitOps repository URL that ArgoCD is watching"
  value       = var.gitops_repo_url
}

output "gitops_repo_branch" {
  description = "Git branch that the Root Application tracks"
  value       = var.gitops_repo_branch
}

output "argocd_access_command" {
  description = "kubectl command to port-forward the ArgoCD UI locally"
  value       = "kubectl port-forward svc/argocd-server -n ${kubernetes_namespace.argocd.metadata[0].name} 8080:443"
}

output "argocd_initial_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password"
  value       = "kubectl get secret argocd-initial-admin-secret -n ${kubernetes_namespace.argocd.metadata[0].name} -o jsonpath='{.data.password}' | base64 -d"
}
