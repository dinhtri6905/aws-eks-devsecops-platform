# ADR-002: ArgoCD App of Apps Pattern

**Status:** Accepted
**Date:** 2025-06-01
**Authors:** NguyenDinhTri

---

## Context

A decision was needed on how to organize ArgoCD Applications across the
platform. Options included: one Application per tool, a single Application
deploying everything, or the App of Apps pattern.

---

## Decision

Use the **App of Apps pattern**: a single Root Application watches a
directory of child Application manifests. ArgoCD creates, updates, and
deletes child Applications based on what files exist in that directory.

---

## Rationale

**Single bootstrap action.** The only manual step after `terraform apply`
is applying one file (`root-app.yaml`). The Terraform argocd-bootstrap
module does this automatically. Everything else flows from Git.

**Adding a new platform tool is a Git operation.** To deploy a new
cluster add-on, create a new Application manifest file in
`argocd/applications/` and push. No ArgoCD UI interaction, no additional
`kubectl apply` calls, no documentation of manual steps.

**Sync waves provide deployment ordering.** Wave annotations on child
Applications ensure Gatekeeper is active before Online Boutique deploys,
and Metrics Server is running before HPA can function.

**Drift detection on the Application layer itself.** If someone manually
creates or deletes an ArgoCD Application on the cluster, the Root App
will revert it. The set of deployed Applications is as much a part of
the desired state as the resources those Applications deploy.

---

## Trade-offs Accepted

- An additional layer of indirection — the Root App must sync before child
  Applications can sync. A failure at the Root App level blocks everything.
- Debugging requires understanding which Application owns which resources.
  The ArgoCD UI makes this visible but it requires familiarity.

---

## Alternatives Considered

**One large Application deploying all resources:**
Rejected because it provides no deployment ordering, makes debugging
difficult (all resources in one sync), and makes it impossible to
independently redeploy a single platform component.

**Manually creating each Application via ArgoCD UI or CLI:**
Rejected because it is not reproducible, not version-controlled, and
requires manual steps that are easy to forget or perform out of order.
