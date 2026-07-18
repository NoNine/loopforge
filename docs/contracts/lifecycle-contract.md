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
- An exact input-bound completion record may return `already-complete` without
  target mutation. This is the only completed-state rerun supported by v1,
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
- OS dependency provisioning is a separate prerequisite checkpoint. It may run
  before application artifact preparation or staging, but it does not authorize
  runtime identity, product-home, application, or service mutation.
- The operator account is a target-provisioning prerequisite. Jenkins shared
  identity and storage remain later shared integration work.

Runtime identity and installed application state are separate classifications.
A fully matching runtime identity with an empty canonical product home may be
adopted for initial setup. Role application files, configuration, service
definitions, runtime data, or an unbound completion record are existing
application state, not reusable identity state.

Initial setup stops before mutation when application state exists unless an
exact completion record binds it to the same mode-appropriate inputs,
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

## Lifecycle Checkpoints

Loopforge setup advances through the following product checkpoints. Each has
one semantic owner, one mutation boundary, and evidence obligations.

| Checkpoint | Owner | Product boundary |
| --- | --- | --- |
| Input review or source selection | Human operator or machine runner | Review target-deployment inputs or select simulation source inputs and supported overrides. No target mutation. |
| OS dependency provisioning | Role helper or native operator procedure | Install approved OS prerequisites without creating product runtime identities, product homes, application state, or service state. |
| Artifact preparation | Bundle factory through role helpers or native procedure | Prepare application artifacts, manifests, checksums, and source-boundary labels without mutating target hosts. |
| Artifact staging | Actor or simulation utility | Transfer prepared artifacts to target staging and verify target-side checksums and required manifests. This checkpoint changes staging only; role setup owns runtime and application mutation. |
| Role-local setup | Role helper or native operator procedure | Create or adopt the exact reviewed runtime identity, install and configure fresh role-local state, and establish its runtime. Exact completed state is a non-mutating no-op; other existing application state blocks. |
| Role-local validation | Role helper or native operator procedure | Combine prior checkpoint outcomes with current observational service, endpoint, and application checks without replay, cross-role claims, or repair. |
| Integration preflight | Shared integration helper or native operator procedure | Observe all three role-readiness handoffs, bound inputs, target inventory, administrator access, selected execution state, and mode support. No target mutation. |
| Reviewed integration access (`target-deployment` only) | Shared integration helper or native operator procedure | Create the integration account/group and the reviewed global and project Gerrit changes, then wait until both changes are externally submitted and effective. Simulation does not support or complete this checkpoint. |
| Shared integration setup | Shared integration helper or native operator procedure | For target deployment, require effective reviewed access. For simulation, apply and validate ACLs as `simulation-only direct Gerrit REST apply` within this checkpoint. Then create the initial keys, public-key authorization, token, credentials, shared storage, node registration, and Gerrit Trigger state. Exact completed state is a non-mutating no-op; other existing state blocks. |
| Cross-role validation | Shared integration helper or native operator procedure | Observe effective access, SSH paths, key custody, storage, node state, and Gerrit Trigger connection without creating, repairing, or replacing state. |
| End-to-end trigger verification | Shared integration helper or native operator procedure | Create only the declared disposable job and change, observe event delivery and agent execution, post the vote, and verify final Gerrit review state. |
| Evidence audit | Global evidence collector and actor review | Validate evidence completeness, redaction, artifact references, input binding, mode labels, and bounded logs without creating runtime success. |

Each mutating checkpoint requires bound inputs, a bounded log reference, and a
resumable status or evidence boundary. Passing evidence represents real checks
for the claimed checkpoint. Unsupported, unimplemented, unavailable, or
modeled behavior is `blocked`, `unsupported`, or `not-applicable`, never
`pass`.

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

Role application artifact bundles remain separate from later integration key
and public-key handoff state. The artifact bundle contract owns their contents;
this contract owns only that integration-owned credentials and handoffs occur
after role readiness and mode-appropriate effective integration access.

## Review Wait, Resume, And Existing State

Integration status, completion state, and evidence boundaries bind to the same
inputs, target identities, mode, and selected execution state. Target review
wait and completion state also bind both Gerrit review identifiers. A later
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
- `simulation/docs/shared/checkpoint-acceptance-protocol.md` owns acceptance and
  publication of owning-layer results and evidence into the simulation ledger;
- `simulation/docs/shared/terminal-output.md` owns shared terminal presentation; and
- backend implementation designs own module boundaries and mechanisms.

Every realization must preserve this product phase order, checkpoint
ownership, mutation boundaries, resume rules, and evidence obligations.
