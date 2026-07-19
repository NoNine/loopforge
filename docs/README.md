# Loopforge Documentation

## Purpose

This document is the documentation entrypoint for Loopforge. It defines how
operators, agents, and reviewers navigate the documentation, choose the
authoritative document for a fact, relate stable docs to mutable execution
state, and review documentation changes.

Loopforge uses layered documentation authorities. A fact should live in the
lowest document that owns it, and consumer docs should link to or narrowly
apply that fact instead of restating the full policy.

## Documentation Map

- `product/` owns product goals, boundaries, and acceptance criteria.
- `architecture/` owns the conceptual system model.
- `contracts/` owns lifecycle and cross-cutting behavioral contracts.
- `baselines/` owns component versions and package prerequisites.
- `operations/` owns the operator interface contract and contains setup
  manuals and native operation references.
- `planning/` contains the implementation roadmap and per-step plans.
- `issues/` contains historical issue reports and root-cause analyses.
- `references/` contains non-authoritative research and historical input.

Simulation realization documents are centralized under `simulation/docs/`;
`simulation/docs/README.md` is their navigation entrypoint. The shared,
Docker, and VM subtrees preserve their owning scope while the
backend CLIs and implementation remain under `simulation/docker/` and
`simulation/vm/`. Mutable repository resume state lives outside the stable
documentation tree in `project-state/execution-status.md`.

## Authority Layers

Use this order when deciding where a product or process fact belongs:

1. `docs/product/prd.md` owns product goals, non-goals, requirements, acceptance
   criteria, and v1 product boundaries.
2. `docs/architecture/system-model.md` owns the conceptual architecture:
   environments, actors, utilities, services, interfaces, deployment modes,
   and cross-cutting system invariants. It must remain substantive, but it is
   not the documentation index.
3. `docs/contracts/lifecycle-contract.md` owns temporal behavior: phase order,
   product checkpoint and checkpoint-result semantics, result ownership,
   mutation boundaries, stop/review/resume points, rerun rules, product workflow
   order, and lifecycle evidence obligations.
4. Topic authority docs own detailed cross-cutting contracts:
   `docs/contracts/account-model.md` for accounts and credential custody,
   `docs/contracts/directory-model.md` for target-visible runtime path
   ownership,
   `docs/baselines/version-baseline.md` for default component versions,
   `docs/baselines/package-requirements.md` for host and package prerequisites,
   `docs/contracts/artifact-bundle-contract.md` for artifact contents and source
   boundaries, `docs/contracts/endpoint-identity.md` for hostnames, URLs, SSH
   host strings, and LDAP endpoint identity,
   `docs/contracts/validation-and-evidence.md` for structured checkpoint-result
   content, evidence, and redaction,
   `docs/contracts/gerrit-trigger-integration.md` for Gerrit Trigger and
   `Verified` behavior, and `docs/contracts/ci-model.md` for external product
   CI configuration ownership and generated Jenkins job modeling.
5. `docs/operations/README.md` owns native and helper operator interface parity
   and the responsibilities of their operation documents.
6. Native operation references own the direct OS and application procedures
   and are the procedural baseline for operation documentation:
   `docs/operations/native/gerrit.md`,
   `docs/operations/native/jenkins-controller.md`,
   `docs/operations/native/jenkins-agent.md`, and
   `docs/operations/native/integration.md`. These references must
   remain free of repository helper command transcripts.
   `docs/operations/native/acceptance-checklist.md` applies the native
   references as one manual `target-deployment` acceptance gate without
   becoming another command reference.
7. Setup manuals own the repository-assisted application of the model and
   lifecycle contract:
   `docs/operations/setup/gerrit.md`,
   `docs/operations/setup/jenkins-controller.md`,
   `docs/operations/setup/jenkins-agent.md`, and
   `docs/operations/setup/integration.md`. They must remain aligned with the
   native procedural baseline and produce equivalent product state and
   validation outcomes. `docs/operations/setup/acceptance-checklist.md` records
   human acceptance of helper-assisted `target-deployment` checkpoints without
   making helper evidence an authorization record.
8. Simulation docs own simulation realization details:
   `simulation/docs/README.md` routes readers without owning behavior;
   `simulation/docs/shared/simulation-model.md` owns the shared public model;
   `simulation/docs/shared/generated-state-layout.md` owns host-side generated
   storage; the other documents under `simulation/docs/shared/` own shared
   architecture, lifecycle state, run-plan transitions, operation records, and
   presentation; and
   `simulation/docs/docker/` and `simulation/docs/vm/` own concrete backend
   guides and realization details.
9. Helper scripts, templates, examples, tests, and verifiers implement or
   check the documented model. They should not become the only place where a
   product behavior is defined.

When layers conflict, update the higher authority or the stale consumer in the
same logical change. Do not preserve contradictory text for compatibility.

## Reference Material

`docs/references/` contains non-authoritative research notes and historical
input. These documents can inform product decisions, implementation plans, or
future docs changes, but they do not define current Loopforge behavior.

When reference material conflicts with authority docs, update the authority
doc only when the product decision changes. Otherwise, treat the reference
material as stale or contextual input.

## Issue Reports

`docs/issues/` contains historical issue reports and root-cause analyses for
maintainers, reviewers, and operators. These reports preserve observed impact,
timelines, evidence references, causal analysis, resolutions, and remaining
validation at the time they are written.

Issue reports are not product, lifecycle, simulation, or mutable-state
authorities. Current behavior remains in the authority and simulation docs,
and current resume state remains in `project-state/execution-status.md`. When
an issue report conflicts with either, treat the report as historical context.

## Execution Ledger Role

`project-state/execution-status.md` is a mutable resume ledger. It may record
current state, accepted commits, verification log paths, guardrails, waivers,
blockers, and the next authorized work item.

Ledger entries should be compressed resume snapshots, not chronological
narratives; detailed investigation belongs in bounded logs.

The ledger must not define product behavior, override stable docs, or become a
second implementation plan. If a completed step changes product behavior,
update the relevant authority document and then record only the resume or audit
fact in the ledger.

## Implementation Plan And Companion Docs

`docs/planning/implementation-plan.md` is the roadmap index for sequencing,
scope, verification, and acceptance. Detailed per-step plans may live under
`docs/planning/steps/`. Implementation plans must not become second authority
documents, resume ledgers, or the durable home for product facts.

Completed steps in the implementation plan should be compressed to historical
sequencing context once their behavior is accepted. Current product behavior
belongs in the stable authority docs, scripts, templates, simulations, and
tests. Mutable status, verification logs, blockers, waivers, and next-work
facts belong in `project-state/execution-status.md`.

Create or update a task-local companion doc when an implementation step needs
durable design detail that would otherwise bloat the roadmap, such as module
boundaries, milestone slices, state machines, command sequences,
cross-subsystem contracts, or failure-mode rules. The implementer should add
the companion doc before or alongside the complex implementation; reviewers
should ask for one when roadmap text starts accumulating subsystem design.

Companion docs should live with the scope they describe:

- Product or process truth belongs in the stable authority docs.
- Public behavior belongs in the owning public docs.
- Internal implementation design belongs near the implementation it describes.
- Mutable status, verification logs, blockers, waivers, and next-work facts
  belong in the execution ledger.
- Decision rationale belongs in the narrowest stable document that owns the
  decision; create a dedicated decision record only when no existing authority
  or companion doc fits cleanly.

The implementation plan should point to companion docs with "read this before
implementing" guidance. Companion docs do not replace the authority layer, and
they must link to or narrowly apply authority facts instead of redefining
product behavior.

## AI Agent Workflow

Before changing docs, an agent should:

1. Read the user request and identify whether it changes product intent,
   system behavior, a topic contract, a procedure, simulation behavior, or only
   resume state.
2. Read the matching authority document before editing any consumer doc.
3. Search for nearby consumer references that will drift if only the authority
   changes.
4. Keep changes scoped to one logical documentation concern.
5. Preserve bounded log handling, evidence redaction, and v1 product boundary
   language.

For implementation tasks, agents should also read
`docs/planning/implementation-plan.md`, the relevant per-step plan under
`docs/planning/steps/` when one exists, and
`project-state/execution-status.md` to understand sequencing and active
guardrails. Those files do not replace the authorities listed above.

When an authority document names implementation, design, sequence, schema, or
contract companion documents for a specific task area, agents must read those
companion documents before editing code, tests, helpers, or consumer docs in
that area. Companion documents do not replace the authority layer; they provide
the task-local implementation context needed to apply it correctly.

## Review Checklist

Use this checklist for documentation changes:

- The changed fact lives in its authority document.
- Consumer docs repeat only the procedure-specific detail they need.
- `docs/architecture/system-model.md` remains the conceptual architecture
  authority rather than a generic documentation index; new topic docs need a
  distinct contract or detail role.
- Lifecycle phase order, product checkpoint semantics, mutation boundaries, and
  resume/rerun behavior live in `docs/contracts/lifecycle-contract.md`.
- Product boundary language remains intact: v1 is not a strict air-gapped
  installer, offline Ubuntu dependency bundles are unsupported, and public
  internet fallback on target hosts is simulation-only and labeled as such.
- `root` is not introduced as a Loopforge account or direct login identity;
  unavoidable privileged target operations are described as delegated
  privilege from the operator account.
- Role manuals and helper behavior stay aligned when a lifecycle behavior
  changes.
- Native operation references stay free of repository helper commands and
  helper-equivalent transcripts.
- Evidence, logs, summaries, and examples avoid private keys, passwords,
  tokens, LDAP bind secrets, and verbose runtime log dumps.
- `project-state/execution-status.md` records only resume or audit state.

Automated documentation contract tests protect repeated drift patterns. They
supplement rather than replace this required review checklist.
