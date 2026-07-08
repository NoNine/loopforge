# Gerrit/Jenkins Setup Package Implementation Plan

## Purpose

This document is the compact implementation roadmap for the v1
Gerrit/Jenkins setup package described in `docs/prd.md`. It records sequence,
scope, current step links, and global acceptance gates. It is not the stable
product authority; use `docs/docs-management.md` to resolve the owning
authority for product, process, simulation, and implementation facts.

Detailed per-step plans live under `docs/implementation/`. Read the index by
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

- Use `docs/docs-management.md` as the single general authority-order
  reference; do not restate that order in individual steps.
- Use `docs/implementation/<step>.md` for task-local plan detail.
- Read companion docs named by the active step before editing code, tests,
  helpers, or consumer docs in that area.
- Use `docs/execution-status.md` only for mutable resume state, active
  guardrails, verification logs, blockers, and next authorized work.
- Product facts belong in the proper authority doc before or alongside
  implementation.

## Global Gates

These gates apply to every implementation step:

- Public command behavior must be functional for the lifecycle phase it
  advertises or fail nonzero with a clear blocked or unsupported reason.
- Lifecycle semantics are owned by `docs/lifecycle-contract.md`.
- Version expectations are owned by `docs/version-baseline.md`.
- Evidence schema, labels, redaction, and aggregation rules are owned by
  `docs/validation-and-evidence.md`.
- Source boundaries and artifact contents are owned by
  `docs/artifact-bundle-contract.md` and the relevant role manuals.
- Documentation changes must pass the review rules in `docs/docs-management.md`.

## Current Roadmap

| Step | Status | Plan | Intent |
| --- | --- | --- | --- |
| 1 | Accepted | `docs/implementation/step-01-repository-structure.md` | Establish repository layout. |
| 2 | Accepted | `docs/implementation/step-02-account-model.md` | Define account and credential custody model. |
| 3 | Accepted | `docs/implementation/step-03-simulation-model.md` | Define shared Docker and VM simulation model. |
| 4 | Accepted | `docs/implementation/step-04-operator-workflow-contract.md` | Define lifecycle workflow contract. |
| 5 | Accepted | `docs/implementation/step-05-gerrit-trigger-integration.md` | Define Gerrit Trigger and `Verified` integration. |
| 6 | Accepted | `docs/implementation/step-06-shared-docker-harness.md` | Add shared Docker role-gate harness. |
| 7 | Accepted | `docs/implementation/step-07-gerrit-manual-and-helper.md` | Add Gerrit role manual, templates, and helper. |
| 8 | Accepted | `docs/implementation/step-08-jenkins-controller-manual-and-helper.md` | Add Jenkins controller manual, templates, and helper. |
| 9 | Accepted | `docs/implementation/step-09-jenkins-agent-manual-and-helper.md` | Add Jenkins agent manual, templates, and helper. |
| 10 | Accepted | `docs/implementation/step-10-validation-and-evidence.md` | Standardize validation and evidence collection. |
| 11 | Accepted | `docs/implementation/step-11-docker-simulation.md` | Build full Docker simulation. |
| 12 | Accepted | `docs/implementation/step-12-shared-simulation-support-library.md` | Extract backend-neutral simulation helpers. |
| 12a | Accepted | `docs/implementation/step-12a-docker-harness-modularization.md` | Modularize Docker harness internals. |
| 13 | In progress | `docs/implementation/step-13-vm-simulation-harness.md` | Implement VM simulation harness milestone by milestone. |
| 14 | Pending | `docs/implementation/step-14-boundary-checks.md` | Add cross-repository boundary checks. |
| 15 | Pending | `docs/implementation/step-15-final-acceptance.md` | Run and document final end-to-end acceptance. |

## Active Step

Step 13 is the active implementation area. Its detailed plan is
`docs/implementation/step-13-vm-simulation-harness.md`; follow that file plus
its named companion docs for VM harness implementation work.

## Commit Strategy

Keep commits small and logical. Use standard Git-style commit messages with
concise imperative subjects, for example:

```text
Add Gerrit setup helper
Add Docker role gate harness
Add Docker simulation verification
Document validation evidence
```
