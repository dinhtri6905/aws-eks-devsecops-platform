# ADR-005: OPA Policy Gate in Terraform CD Pipeline

**Status:** Accepted
**Date:** 2025-06-01
**Authors:** NguyenDinhTri

---

## Context

A decision was needed on where to enforce infrastructure security policies:
at plan time (before apply), at apply time (via AWS Config or SCPs), or
post-deployment (via audit tools).

---

## Decision

Enforce policies **at plan time** using OPA to evaluate the Terraform
plan JSON before any infrastructure change is applied.

```
plan --> opa-gate --> deploy
```

The OPA gate evaluates the exported plan JSON against three policy
files and fails the pipeline if any deny violations are found.

---

## Rationale

**Shift left.** Finding a policy violation during `terraform plan` takes
seconds. Finding it after `terraform apply` requires manually reverting
infrastructure changes that may have side effects (modified security
groups, deleted subnets). The cost of a false positive is negligible;
the cost of a missed violation post-apply is significant.

**Plan JSON is a complete representation of intent.** `terraform show -json`
produces a structured document containing every resource change, its
before/after state, and the configuration values. OPA can evaluate this
document with full access to the planned changes without needing AWS
credentials.

**Three independent policy domains.**
Splitting policies into `security.rego`, `networking.rego`, and
`compliance.rego` makes each file focused and testable independently.
A security engineer can review the security policy without understanding
the networking rules.

**Warnings are non-blocking.** Not every policy violation requires
blocking deployment. The `warn` rule set produces findings that are
logged and reported without failing the pipeline. This allows the team
to introduce new policies in warning mode before promoting them to
deny rules.

**The binary plan is the artifact that gets applied.**
The deploy job downloads and applies the exact binary plan that the
OPA gate evaluated. There is no risk of the infrastructure state
changing between evaluation and application — the plan file is
cryptographically tied to the specific Terraform run via `github.sha`.

---

## Trade-offs Accepted

- OPA policies must be maintained alongside Terraform modules. When a
  new resource type is added to the platform, the relevant policy file
  should be updated to cover it.
- Rego is a specialized language. Engineers unfamiliar with Rego may
  find policies harder to read than equivalent imperative code.
- The OPA evaluation runs against the plan JSON, not against the live
  AWS state. Policy violations on existing infrastructure that are not
  changing are not caught by this gate (they are the responsibility of
  the nightly `check-scan.yaml` workflow).

---

## Alternatives Considered

**AWS Config Rules (post-deployment):**
Rejected as the primary control because it detects violations after
infrastructure has already been created. Remediating a mis-configured
security group or unencrypted RDS instance after deployment is more
disruptive than preventing it at plan time.

**Sentinel (HashiCorp):**
Rejected because it requires Terraform Cloud or Terraform Enterprise.
The platform uses the open-source Terraform CLI with an S3 backend.

**Manual review only:**
Rejected because human review of Terraform plans is error-prone and
does not scale. Automated policy evaluation is consistent and fast.
