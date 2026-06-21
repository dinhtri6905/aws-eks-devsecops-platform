# ADR-004: Rolling Updates Instead of Blue-Green Deployment

**Status:** Accepted
**Date:** 2025-06-01
**Authors:** NguyenDinhTri

---

## Context

A decision was needed on the deployment strategy for Online Boutique
microservices. Options considered: rolling updates (Kubernetes default),
blue-green deployment, and canary releases.

---

## Decision

Use **Kubernetes rolling updates** for the dev environment.
Blue-green deployment is documented as a future improvement for prod.

---

## Rationale

**Rolling updates are zero-downtime for stateless services.**
All Online Boutique microservices are stateless (session state is
in Redis). Rolling updates replace pods one at a time, ensuring
at least one pod is always running and passing its readiness probe
before the next is replaced. Downtime is not a concern.

**Rolling updates are the Kubernetes default.** No additional tooling,
configuration, or operator is required. The deployment strategy is
declared in the Deployment spec and ArgoCD applies it automatically.

**Blue-green requires additional infrastructure.** A true blue-green
deployment requires two complete environments and a mechanism to shift
traffic between them (typically at the load balancer level). This doubles
resource consumption and requires additional tooling (Argo Rollouts or
equivalent) that adds operational complexity.

**Dev environment does not require zero-downtime guarantees.**
The dev environment is used for testing and development, not for
serving end users. The additional complexity of blue-green is not
justified by the risk profile.

---

## Trade-offs Accepted

- During a rolling update, old and new versions of a service run
  simultaneously for a brief period. API compatibility between versions
  must be maintained.
- Rollback is slower than blue-green (requires a new rolling update
  rather than an instant traffic shift). ArgoCD rollback initiates
  a new rollout rather than instant cutover.

---

## Future Path

Argo Rollouts can be introduced to enable blue-green or canary
deployments in prod without changing the ArgoCD integration. The
Rollout resource is a drop-in replacement for Deployment. This
is listed in the platform roadmap.
