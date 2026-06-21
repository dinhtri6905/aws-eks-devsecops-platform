# ADR-001: Monorepo Structure

**Status:** Accepted
**Date:** 2025-06-01
**Authors:** NguyenDinhTri

---

## Context

A decision was needed on whether to use a single repository (monorepo)
for all platform concerns, or separate repositories for infrastructure,
GitOps manifests, and application code (polyrepo).

---

## Decision

Use a **monorepo** with clear directory separation between concerns.

```
aws-eks-devsecops-platform/
  .github/workflows/       -- CI/CD pipelines
  microservices-application/ -- application source code
  platform/
    infrastructure/        -- Terraform
    gitops/                -- ArgoCD + Kustomize
  docs/                    -- documentation
  policies/                -- OPA policies
```

---

## Rationale

**Cross-cutting changes are atomic.** When a new microservice is added,
the Terraform ECR module, the Kubernetes manifests, the ArgoCD Application,
and the CI/CD pipeline all need updating. A monorepo allows these changes
to be reviewed and merged in a single Pull Request. A polyrepo requires
coordinating changes across multiple PRs in multiple repositories.

**Reduced operational overhead.** A single repository means one set of
branch protection rules, one GitHub Actions quota, one secret configuration,
and one place to search for any file in the system.

**Simpler developer onboarding.** A new team member clones one repository
and has everything they need. There is no repository discovery problem.

**Visibility into cross-cutting concerns.** A security engineer reviewing
a change to an OPA policy can see the Terraform module and the Kubernetes
manifests in the same PR context.

---

## Trade-offs Accepted

- Pull Request diffs may be larger when multiple concerns change together
- Terraform and application CI pipelines use path filters to avoid
  unnecessary runs — this adds some complexity to the pipeline configuration
- Repository size will grow over time as history accumulates across all concerns

---

## Alternatives Considered

**Polyrepo (infrastructure + gitops + application as separate repos):**
Rejected because atomic cross-cutting changes are impossible, and the
coordination overhead between repositories does not benefit a team of this
size.

**Monorepo with separate top-level apps directory:**
The Online Boutique source code lives under `microservices-application/`
rather than a top-level `apps/` to keep it clearly separated from the
platform infrastructure. This is a naming convention, not an architectural
difference.
