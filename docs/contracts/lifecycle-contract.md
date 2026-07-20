# Loopforge Product Lifecycle Contract

## Purpose And Authority

This document owns the product-level temporal contract for Loopforge setup in
every supported execution mode. It defines phase behavior, checkpoint order,
ownership and mutation boundaries, review and resume points, rerun behavior,
and the conditions under which later product work may begin.

This contract does not define concrete command syntax, backend resource
lifecycle, simulation run/set schemas, generated paths, transport adapters,
terminal output, or detailed role procedures. Those facts belong to the
operator, simulation, state-model, and implementation documents named under
Realization Boundaries below.

`docs/architecture/system-model.md` owns the conceptual environments, actors,
utilities, services, interfaces, deployment modes, and system invariants. This
contract applies that model to product workflow sequencing. Consumer documents
may add role- or mode-specific realization detail, but they must not redefine
checkpoint semantics or claim success without proof for the owned checkpoint.

## Checkpoint Terminology

Use these terms consistently across product, operator, evidence, and simulation
documents:

- A **phase** is one invocation or activity performed by an owner. It may
  succeed, fail, or block without completing its intended checkpoint.
- A **product checkpoint family** is one semantic milestone category in the
  canonical table below.
- A **product checkpoint instance** applies one family to a concrete owner and
  scope, such as role-local setup for Gerrit. A product checkpoint instance is
  complete only when its required postcondition and proof have passed the
  mode-specific coordination boundary.
- A **checkpoint result** is the product checkpoint owner's outcome and
  supporting proof for one checkpoint attempt. It identifies the checkpoint
  instance and binds the claimed postcondition or observation to the applicable
  product inputs, target identity, and safe proof. The concept does not require
  a particular file format: a native procedure may present observations
  directly, while a helper or other machine utility emits a structured
  checkpoint result defined by the evidence contract.
- A **human acceptance authority** evaluates the checkpoint result and proof
  for target deployment and records an organizational accept or block
  decision.
- A **human acceptance record** is that authority's durable target-deployment
  decision. Only an affirmative decision authorizes later target work.
- A **simulation run plan** is the ordered realization of applicable product
  checkpoint instances for one selected simulation run.
- A **run-step record** is the simulation harness's immutable record that it
  verified and captured one structured checkpoint result and committed the
  corresponding run-plan transition under the selected set lock. It documents
  the transition; the record alone does not cause or authorize one.
- A **simulation operation record** is the simulation operation owner's
  retained outcome and proof for resource lifecycle work such as `create`,
  `start`, `stop`, restoration, cleanup, or destruction. It is not a checkpoint
  result, run-step record, or human acceptance record.
- A **presentation summary** is a projection of checkpoint results, accepted
  target state, or committed simulation state for an operator. It creates no
  result or record and must identify the authoritative record when it reports
  accepted or committed state.
- A **prerequisite** is a required condition and a **boundary** is a stop,
  review, or mutation limit. Neither should be called a checkpoint unless it is
  one of the product checkpoint families below.

Unless explicitly qualified, "checkpoint" in product and operator documents
means a product checkpoint. Simulation documents use "run step" for one
product-checkpoint realization in the simulation run plan and "run-step
record" for its persisted transition record. Do not use "checkpoint marker" as
a generic name for checkpoint results, run-step records, operation records, or
human acceptance records.

## Acceptance And Authorization

Every execution mode preserves the product owner separately from its mode
coordinator even when one operator-facing document presents both:

1. The owning utility or procedure produces one mode-appropriate checkpoint
   result containing its outcome, binding, and supporting proof. Native
   procedures may present observed results directly; helpers and other machine
   utilities emit structured checkpoint results.
2. In target deployment, the human acceptance authority evaluates that result
   and proof and writes the human acceptance record.
3. In simulation, the harness verifies and captures the exact structured
   checkpoint result, verifies the run-plan guards, atomically advances the
   run-plan head, and retains the resulting run-step record.
4. Terminal output, evidence summaries, and final reports project checkpoint
   results, target acceptance, operation state, or run-plan state without
   creating them.

The three execution modes map those layers as follows:

| Execution mode | Product owner output | Mode coordination | Durable coordination record | Presentation |
| --- | --- | --- | --- | --- |
| Docker simulation | Product-owner structured checkpoint result | Harness verifies and captures the result, verifies guards, and commits the next run-plan transition | Hash-linked run-step record | Projection of checkpoint results, operation state, and run-plan head |
| VM simulation | Product-owner structured checkpoint result | Harness verifies and captures the result, verifies guards, and commits the next run-plan transition | Hash-linked run-step record | Projection of checkpoint results, operation state, and run-plan head |
| Target deployment | Native observed checkpoint result, or helper-owned structured checkpoint result | Human operator or reviewer accepts or blocks | Human acceptance record | Human-readable acceptance result and its supporting references |

Simulation run-plan coordination preserves product checkpoint order and proof
boundaries but is not product, organizational, risk, waiver, or deployment
acceptance.

A favorable checkpoint result, phase success, target acceptance, committed
simulation run-plan progress, and final run completion are distinct claims. A
structured checkpoint result may report `pass` before a target reviewer blocks
it or a simulation harness rejects its binding or cannot commit the run-plan
transition. A simulation run is complete only after every required run step,
including Evidence audit, has a committed run-step record.

Concrete coordination, record schemas and storage, checklist layout, status
vocabulary, and presentation belong to the evidence, operator, and simulation
realization documents named under Realization Boundaries.

## Phase Behavior

Product phases are strict, single-purpose operations:

- Each phase validates its prerequisites before doing work.
- Missing inputs, artifacts, services, or prerequisite checkpoints fail
  clearly and stop.
- Each phase owns only its declared work and does not rerun or repair another
  phase.
- Later phases do not silently trigger earlier phases.
- Repeated invocation is an intentional rerun of that same phase.
- Phase logs and evidence stay bounded and identify the producing phase.
- Phase success means that phase completed its own contract, not that another
  phase was replayed or repaired implicitly.
- A helper may return `already-complete` without target mutation only when an
  exact structured checkpoint result proves completion for the same inputs and
  selected state. This is the only completed-state rerun supported by v1,
  except for the target-deployment review wait defined below.

Environment provisioning, power control, baseline restoration, generated-state
cleanup, and backend destruction do not advance a product checkpoint merely
because they succeeded. A realization may advance a checkpoint only by
performing the checkpoint owner's work and retaining its required proof.

## Role State And Identity

Role preflight and role setup divide runtime identity work as follows:

- Preflight is non-mutating. It validates the reviewed runtime account name,
  primary group name, UID, GID, and canonical product home. Fully absent
  account/group/home state is ready for creation, and fully matching state is
  ready for reuse.
- Partial or conflicting runtime identity state blocks. This includes an
  account without its complete group/home state, a numeric identity collision,
  a mismatched account home or primary group, and a product home with the wrong
  type or ownership.
- Role setup creates a fully absent runtime group, account, and product home
  from reviewed values after staged artifacts have been verified. It may adopt
  a fully matching identity with an empty product home but never repairs
  mismatched identity or existing application state.
- OS dependency provisioning is a separate product checkpoint and a
  prerequisite to role setup. It may run
  before application artifact preparation or staging, but it does not authorize
  runtime identity, product-home, application, or service mutation.
- The operator account is a target-provisioning prerequisite. Jenkins shared
  identity and storage remain later shared integration work.

Runtime identity and installed application state are separate classifications.
A fully matching runtime identity with an empty canonical product home may be
adopted for initial setup. Role application files, configuration, service
definitions, runtime data, or an unbound completion result are existing
application state, not reusable identity state.

Initial setup stops before mutation when application state exists unless an
exact structured checkpoint result binds it to the same mode-appropriate
inputs,
artifacts, target identity, mode, and selected execution state. Exact completed
state returns `already-complete` without starting, stopping, restarting,
rewriting, or deleting target state. Changed, partial, conflicting, or unbound
state requires explicit cleanup, migration, or site-owned administration; v1
role helpers do not reinstall or reconfigure it.

Target operations run as the operator account whenever practical. Direct root
login or root as a workflow identity is unsupported. Delegated privilege from
the operator account is limited to narrow OS operations such as package
installation, protected path creation, service management, or ownership
changes. Runtime accounts own and run their services; they are not the default
orchestration identity.

## Service Lifecycle

Role setup and role validation have separate responsibilities:

- Role setup installs fresh role-local state, configures the service, and
  establishes the initial runtime when the role requires one.
- Jenkins controller role setup includes the complete JCasC ownership handoff:
  apply the protected first-start bootstrap, verify its security baseline,
  detach and remove the automatic JCasC source, restart Jenkins, and prove the
  configuration persists without JCasC. A controller is not ready while its
  normal startup still loads the bootstrap source.
- Role validation is observational. It may collect evidence, but it must not
  start, restart, enable, reconfigure, or repair a role process or service.
- Role validation may consume successful earlier checkpoint results. It must
  not replay their setup or verification operations to restate identity,
  filesystem, artifact, or configuration readiness.
- When an execution mode claims service persistence across an environment
  restart or host reboot, the service must recover before validation begins.
  Validation must report a recovery failure rather than repair the service and
  then claim a passing persistence result.

The architecture and mode-specific realization documents own the concrete
runtime mechanism. That mechanism does not change the setup/validation
ownership boundary.

## Input Authority And Binding

Every mutating product checkpoint requires one reviewed and bound input source:

- target deployment uses reviewed operator inputs; and
- simulation uses actor-selected source inputs followed by one published,
  immutable effective input set.

Later product phases consume the same bound values and must not rewrite or
reinterpret them. Mode-assigned transport observations may be supplied through
a realization-owned invocation boundary, but they must not silently change the
stable product inputs or target identities.

Input selection, rendering, publication, or transport adaptation does not by
itself authorize target mutation or complete a product checkpoint. The
realization must prove that the bound inputs belong to the selected execution
state before checkpoint work begins.

## Product Checkpoint Families

The following table is the canonical product checkpoint family vocabulary.
Each applicable occurrence is a product checkpoint instance with one concrete
owner, one mutation boundary, and evidence obligations. Role-scoped families
expand into separate Gerrit, Jenkins controller, and Jenkins agent instances;
consumer documents must identify the applicable role instead of inventing a
new checkpoint family name.

| Product checkpoint family | Owner | Product boundary |
| --- | --- | --- |
| Input review or source selection | Human operator or machine runner | Review target-deployment inputs and supported overrides. No target mutation. |
| OS dependency provisioning | OS provisioner or native operator procedure | Install approved OS prerequisites without creating product runtime identities, product homes, application state, or service state. |
| Artifact preparation | Bundle factory through role helpers or native procedure | Prepare application artifacts, manifests, checksums, and source-boundary labels without mutating target hosts. |
| Artifact staging | Actor or simulation utility | Transfer prepared artifacts to target staging and verify target-side checksums and required manifests. This checkpoint changes staging only; role setup owns runtime and application mutation. |
| Role-local setup | Role helper or native operator procedure | Create or adopt the exact reviewed runtime identity, install and configure fresh role-local state, and establish its runtime. Exact completed state is a non-mutating no-op; other existing application state blocks. |
| Role-local validation | Role helper or native operator procedure | Combine prior checkpoint outcomes with current observational service, endpoint, and application checks without replay, cross-role claims, or repair. |
| Integration preflight | Shared integration helper or native operator procedure | Observe all three role-readiness handoffs, bound inputs, target inventory, administrator access, selected execution state, and mode support. No target mutation. |
| Reviewed integration access (`target-deployment` only) | Shared integration helper or native operator procedure | Create the integration account/group and the reviewed global and project Gerrit changes, then wait until both changes are externally submitted and effective. Simulation does not support or complete this checkpoint. |
| Shared integration setup | Shared integration helper or native operator procedure | For target deployment, require effective reviewed access. For simulation, apply and validate ACLs as `simulation-only direct Gerrit REST apply` within this checkpoint. Then create the initial keys, public-key authorization, token, credentials, shared storage, node registration, and Gerrit Trigger state. Exact completed state is a non-mutating no-op; other existing state blocks. |
| Cross-role validation | Shared integration helper or native operator procedure | Observe effective access, SSH paths, key custody, storage, node state, and Gerrit Trigger connection without creating, repairing, or replacing state. |
| End-to-end trigger verification | Shared integration helper or native operator procedure | Create only the declared disposable job and change, observe event delivery and agent execution, post the vote, and verify final Gerrit review state. |
| Evidence audit | Evidence auditor and mode coordinator | Confirm that required proof is complete, coherent, safely reviewable, and bound to the claimed execution without creating missing success. |

### Simulation Waivers

Docker and VM simulation waive `Input review or source selection` and `OS
dependency provisioning` from their product run plans. The harness still
establishes equivalent simulation prerequisites, but they remain
simulation-only implementation work:

- `init-run` selects and snapshots simulation source templates and supported
  overrides, then records that work in its simulation operation record.
- Initial `create` provisions or verifies the simulation-owned OS dependency
  baseline and records that work in its simulation operation record.

Neither operation emits a structured checkpoint result or commits a run step.
Target deployment retains both product checkpoints and their normal human
coordination. The waiver does not make simulation inputs or dependencies valid
target-deployment proof.

Each mutating checkpoint requires bound inputs, a bounded log reference, and a
resumable result or evidence boundary. Favorable evidence must represent real
checks for the claimed checkpoint. Unsupported, unimplemented, unavailable, or
modeled behavior cannot satisfy the checkpoint's proof obligation.

Integration preflight rejects unsupported access-control or review behavior
before account, token, key, credential, node, storage, or trigger mutation. An
external approval stop is an expected resumable boundary, not shared setup
success.

## Product Workflow Order

The normal product workflow is:

1. Review or select inputs and complete non-mutating preflight.
2. Provision required OS dependencies.
3. Prepare artifacts in the bundle factory.
4. Stage and verify artifacts on each role target.
5. Complete role setup and observational validation for Gerrit, the Jenkins
   controller, and the Jenkins agent.
6. Complete non-mutating integration preflight.
7. In `target-deployment`, establish reviewed Gerrit access and wait for
   external approval. Simulation omits this checkpoint.
8. Complete shared integration setup, including the simulation-only direct ACL
   realization when in Docker or VM simulation.
9. Perform observational cross-role validation.
10. Perform the active end-to-end trigger proof.
11. Audit and aggregate evidence.

OS dependency provisioning may precede artifact preparation, but both
dependency and staged-artifact checkpoints must pass before role setup. All
three role-readiness handoffs must pass before integration mutation. A
validation or proof phase never supplies missing setup work or replays a
successful owning checkpoint.

In simulation, the two waived checkpoint families above are satisfied as
simulation prerequisites before the applicable product run plan begins at
role-qualified Artifact preparation.

Role application artifact bundles remain separate from later integration key
and public-key handoff state. The artifact bundle contract owns their contents;
this contract owns only that integration-owned credentials and handoffs occur
after role readiness and mode-appropriate effective integration access.

## Review Wait, Resume, And Existing State

Integration checkpoint results and external review boundaries bind to the same
inputs, target identities, mode, and selected execution state. Target review
wait state also binds both Gerrit review identifiers. A later
phase rejects state from different inputs or a different execution; record
existence alone is not a valid prerequisite.

An interrupted target-deployment review wait may resume only with the same
bound inputs and the same two review changes. This external-approval wait is
the only resumable mutation boundary and is outside the simulation checkpoint
ledger. Simulation has no Reviewed Access wait or resume. Exact input-bound
completed integration state returns `already-complete` without mutation.
Stale, partial, conflicting, changed, or unbound state requires explicit
cleanup, migration, site-owned credential administration, or a fresh selected
execution state.

Normal setup does not rotate existing tokens or keys, truncate
`authorized_keys`, remove a working Jenkins credential or node, or delete
role-owned agent runtime state. Loopforge v1 does not provide credential
rotation. State requiring rotation is conflicting existing state and blocks
normal setup.

## Evidence Obligations

`docs/contracts/validation-and-evidence.md` owns evidence schemas, statuses,
redaction, aggregation, and mode-specific fields. This lifecycle contract
requires only that:

- every claimed checkpoint has mode-appropriate proof bound to the same inputs
  and execution state;
- role readiness, cross-role validation, and end-to-end proof remain distinct
  claims;
- evidence and summaries do not expose private keys, passwords, tokens, LDAP
  bind secrets, or secret-bearing input values; and
- evidence audit validates existing proof without manufacturing missing
  success.

Native `target-deployment` records the corresponding role, reboot,
integration, scheduling, trigger, and vote outcomes in
`docs/operations/native/acceptance-checklist.md`. Routine service logs remain
in their normal target locations and are inspected only through bounded reads.
Helper-assisted `target-deployment` records human checkpoint decisions in
`docs/operations/setup/acceptance-checklist.md`; structured helper results are
inputs to those decisions, not acceptance records.

## Realization Boundaries

Concrete procedures and implementation facts live below this contract:

- `docs/README.md` maps account, directory, artifact, endpoint, integration,
  and evidence details to their topic authority documents;
- setup and native manuals own role- and interface-specific operator steps;
- `simulation/docs/shared/simulation-model.md` owns shared simulation command semantics, input
  realization, and resource lifecycle;
- Docker and VM simulation guides own their concrete backend command behavior;
- `simulation/docs/shared/harness-design.md` owns shared harness architecture;
- `simulation/docs/shared/lifecycle-state-model.md` owns exact simulation state
  schemas, guards, classification, transitions, and the product-to-simulation
  checkpoint mapping;
- `simulation/docs/shared/run-plan-transition-protocol.md` owns structured
  checkpoint-result capture and verification plus run-plan transition
  publication;
- `simulation/docs/shared/operation-records.md` owns simulation resource
  lifecycle operation records;
- `simulation/docs/shared/terminal-output.md` owns shared terminal presentation; and
- backend implementation designs own module boundaries and mechanisms.

Every realization must preserve this product phase order, checkpoint
ownership, mutation boundaries, resume rules, and evidence obligations.
