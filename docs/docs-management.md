# Documentation Management

## Purpose

This document is the AI-native documentation entrypoint for Loopforge. It
defines how agents and reviewers choose the authoritative document for a fact,
how stable docs relate to mutable execution state, and what to check before a
documentation change is accepted.

Loopforge uses layered documentation authorities. A fact should live in the
lowest document that owns it, and consumer docs should link to or narrowly
apply that fact instead of restating the full policy.

## Authority Layers

Use this order when deciding where a product or process fact belongs:

1. `docs/prd.md` owns product goals, non-goals, requirements, acceptance
   criteria, and v1 product boundaries.
2. `docs/system-model.md` owns the conceptual architecture: environments,
   actors, utilities, services, interfaces, deployment modes, and
   cross-cutting system invariants. It must remain substantive, but it is not
   the documentation index.
3. `docs/lifecycle-contract.md` owns temporal behavior: phase order,
   checkpoint semantics, mutation boundaries, stop/review/resume points,
   rerun rules, lifecycle command mapping, and lifecycle evidence obligations.
4. Topic authority docs own detailed cross-cutting contracts:
   `docs/account-model.md` for accounts and credential custody,
   `docs/directory-model.md` for path ownership and generated state,
   `docs/version-baseline.md` for default component versions,
   `docs/package-requirements.md` for host and package prerequisites,
   `docs/artifact-bundle-contract.md` for artifact contents and source
   boundaries, `docs/validation-and-evidence.md` for evidence and redaction,
   and `docs/gerrit-trigger-integration.md` for Gerrit Trigger and `Verified`
   behavior.
5. Operator manuals own procedural application of the model and lifecycle
   contract:
   `docs/gerrit-setup-manual.md`,
   `docs/jenkins-controller-setup-manual.md`,
   `docs/jenkins-agent-setup-manual.md`, and
   `docs/integration-setup-manual.md`.
6. Native operation references own direct OS and application procedures:
   `docs/gerrit-native-operations-reference.md`,
   `docs/jenkins-controller-native-operations-reference.md`, and
   `docs/jenkins-agent-native-operations-reference.md`. These references must
   remain free of repository helper command transcripts.
7. Simulation docs own simulation realization details:
   `simulation/README.md`, `simulation/docker/README.md`,
   and `simulation/vm/README.md`.
8. Helper scripts, templates, examples, tests, and verifiers implement or
   check the documented model. They should not become the only place where a
   product behavior is defined.

When layers conflict, update the higher authority or the stale consumer in the
same logical change. Do not preserve contradictory text for compatibility.

## Execution Ledger Role

`docs/execution-status.md` is a mutable resume ledger. It may record current
state, accepted commits, verification log paths, guardrails, waivers, blockers,
and the next authorized work item.

The ledger must not define product behavior, override stable docs, or become a
second implementation plan. If a completed step changes product behavior,
update the relevant authority document and then record only the resume or audit
fact in the ledger.

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

For implementation tasks, agents should also read `docs/implementation-plan.md`
and `docs/execution-status.md` to understand accepted work and active
guardrails. Those files do not replace the authorities listed above.

## Review Checklist

Use this checklist for documentation changes:

- The changed fact lives in its authority document.
- Consumer docs repeat only the procedure-specific detail they need.
- `docs/system-model.md` remains the conceptual architecture authority rather
  than a generic documentation index; new topic docs need a distinct contract
  or detail role.
- Lifecycle phase order, checkpoint semantics, mutation boundaries, and
  resume/rerun behavior live in `docs/lifecycle-contract.md`.
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
- `docs/execution-status.md` records only resume or audit state.

Automated docs contract tests may be added later for repeated drift patterns.
Until then, this checklist is the required review mechanism.
