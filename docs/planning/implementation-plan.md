# Gerrit/Jenkins Setup Package Implementation Plan

## Purpose

This document is the compact implementation roadmap for the v1
Gerrit/Jenkins setup package described in `docs/product/prd.md`. It records sequence,
scope, current step links, and global acceptance gates. It is not the stable
product authority; use `docs/README.md` to resolve the owning
authority for product, process, simulation, and implementation facts.

Detailed per-step plans live under `docs/planning/steps/`. Read the index by
default, then read only the active step file or an explicitly relevant step
file. Completed step details are historical planning context, not current
product truth.

The behavior digest is `docs/references/reference-digest.md`. That digest
summarizes the known-working draft repository behavior without allowing
implementation agents to copy code, docs, templates, scripts, config files,
command bodies, or verbatim implementation from
`/home/ubuntu/ai-assisted/gerrit-jenkins`. Do not open or copy from the draft
repository unless a human explicitly approves a new reference review.

## Using This Plan

This roadmap is subordinate to the authority docs. When a step and an
authority doc conflict, update the stale text in the same logical change
instead of preserving contradictory guidance.

- Use `docs/README.md` as the single general authority-order
  reference; do not restate that order in individual steps.
- Use `docs/planning/steps/<step>.md` for task-local plan detail.
- Read companion docs named by the active step before editing code, tests,
  helpers, or consumer docs in that area.
- Use `project-state/execution-status.md` only for mutable resume state, active
  guardrails, verification logs, blockers, and next authorized work.
- Product facts belong in the proper authority doc before or alongside
  implementation.

## Global Gates

These gates apply to every implementation step:

- Public command behavior must be functional for the lifecycle phase it
  advertises or fail nonzero with a clear blocked or unsupported reason.
- Lifecycle semantics are owned by `docs/contracts/lifecycle-contract.md`.
- Version expectations are owned by `docs/baselines/version-baseline.md`.
- Evidence schema, labels, redaction, and aggregation rules are owned by
  `docs/contracts/validation-and-evidence.md`.
- Source boundaries and artifact contents are owned by
  `docs/contracts/artifact-bundle-contract.md` and the relevant role manuals.
- Documentation changes must pass the review rules in `docs/README.md`.

## Current Roadmap

| Step | Status | Plan | Intent |
| --- | --- | --- | --- |
| 1 | Accepted | `docs/planning/steps/step-01-repository-structure.md` | Establish repository layout. |
| 2 | Accepted | `docs/planning/steps/step-02-account-model.md` | Define account and credential custody model. |
| 3 | Accepted | `docs/planning/steps/step-03-simulation-model.md` | Define shared Docker and VM simulation model. |
| 4 | Accepted | `docs/planning/steps/step-04-operator-workflow-contract.md` | Define lifecycle workflow contract. |
| 5 | Accepted | `docs/planning/steps/step-05-gerrit-trigger-integration.md` | Define Gerrit Trigger and `Verified` integration. |
| 6 | Accepted | `docs/planning/steps/step-06-shared-docker-harness.md` | Add shared Docker role-gate harness. |
| 7 | Accepted | `docs/planning/steps/step-07-gerrit-manual-and-helper.md` | Add Gerrit role manual, templates, and helper. |
| 8 | Accepted | `docs/planning/steps/step-08-jenkins-controller-manual-and-helper.md` | Add Jenkins controller manual, templates, and helper. |
| 9 | Accepted | `docs/planning/steps/step-09-jenkins-agent-manual-and-helper.md` | Add Jenkins agent manual, templates, and helper. |
| 10 | Accepted | `docs/planning/steps/step-10-validation-and-evidence.md` | Standardize validation and evidence collection. |
| 11 | Accepted | `docs/planning/steps/step-11-docker-simulation.md` | Build full Docker simulation. |
| 12 | Accepted | `docs/planning/steps/step-12-shared-simulation-support-library.md` | Extract backend-neutral simulation helpers. |
| 12a | Accepted | `docs/planning/steps/step-12a-docker-harness-modularization.md` | Modularize Docker harness internals. |
| 13 | In progress | `docs/planning/steps/step-13-vm-simulation-harness.md` | Implement VM simulation harness milestone by milestone. |
| 13a | In progress | `docs/planning/steps/step-13a-reusable-simulation-lifecycle.md` | Align reusable lifecycle and the backend-local run-planning foundation. |
| 13b | Pending | `docs/planning/steps/step-13b-fresh-state-role-lifecycle.md` | Align role behavior and attach the role checkpoint tail to run planning. |
| 13c | Pending | `docs/planning/steps/step-13c-shared-integration-lifecycle.md` | Attach the integration/evidence tail and accept full composite workflows. |
| 14 | Pending | `docs/planning/steps/step-14-boundary-checks.md` | Add cross-repository boundary checks. |
| 15 | Pending | `docs/planning/steps/step-15-final-acceptance.md` | Run and document final end-to-end acceptance. |

## Active Step

Step 13 is the active implementation area. Its detailed plan is
`docs/planning/steps/step-13-vm-simulation-harness.md`; follow that file plus
its named companion docs for VM harness implementation work. Step 13a first
aligns reusable simulation lifecycle behavior and the backend-local `run`
planning foundation. Its M1-M4 implementation baseline feeds the shared and
Docker cutover in M5, VM parity in M6, cross-backend recovery alignment in M7,
run-plan selection in M8, and lifecycle handoff in M9. Step 13b attaches the
three role checkpoint families, and Step 13c attaches the integration/evidence
tail and owns full composite runtime acceptance. All three are required before
Step 13 integration acceptance can close and before Steps 14 and 15 begin.

## Commit Strategy

Keep commits small and logical. Use standard Git-style commit messages with
concise imperative subjects, for example:

```text
Add Gerrit setup helper
Add Docker role gate harness
Add Docker simulation verification
Document validation evidence
```
