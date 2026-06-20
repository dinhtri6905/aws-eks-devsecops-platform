# ADR-003: Kustomize for Application Layer, Helm for Platform Tools

**Status:** Accepted
**Date:** 2025-06-01
**Authors:** NguyenDinhTri

---

## Context

A decision was needed on whether to use Kustomize or Helm for managing
Kubernetes manifests, both for platform tools (LBC, Gatekeeper, Falco,
Prometheus) and for the Online Boutique application.

---

## Decision

Use **Helm charts for platform tools** (referenced via `helmCharts:`
in Kustomize) and **Kustomize overlays for the application layer**
(Online Boutique).

---

## Rationale

**Platform tools have official Helm charts maintained by their authors.**
Using the official Helm chart for Gatekeeper, Falco, and Prometheus
means security patches and new features are available by bumping a version
number. Writing and maintaining custom YAML for these tools would be
significantly more work and risk.

**The application layer benefits from Kustomize's overlay model.**
Online Boutique needs to run differently in dev (1 replica, debug config)
and prod (2+ replicas, HPA, stricter limits). Kustomize patches apply
these differences without duplicating base manifests. A change to a
service's health probe config goes in one place (base) and propagates
to all environments.

**Helm values are declarative and version-controlled.** Even though the
platform tools are deployed via Helm, their values files live in Git and
are diff-able in Pull Requests. There is no "config drift" from manual
Helm value changes.

**ArgoCD supports both natively.** ArgoCD's `helmCharts:` block in
Kustomize, and its `spec.source.helm` in Application manifests, allow
Helm and Kustomize to be mixed within the same GitOps workflow.

---

## Trade-offs Accepted

- Engineers need to understand both Kustomize and Helm to work on the
  platform. The two tools have different mental models.
- Debugging a Helm-rendered resource requires either `helm template` or
  looking at the ArgoCD diff view.

---

## Alternatives Considered

**Kustomize for everything (including platform tools):**
Rejected because it would require maintaining raw manifests for Gatekeeper,
Falco, and Prometheus — hundreds of lines of YAML that the upstream
maintainers already manage via Helm. Every upstream release would require
manual YAML updates.

**Helm for everything (including Online Boutique):**
Rejected because Online Boutique is an application where we control
the manifests directly. Helm's templating would add complexity without
benefit. Kustomize's strategic merge patches are more readable and
explicit for simple environment differences like replica counts.
