# Step 13b: Align Fresh-State Role Lifecycle

Align the Gerrit, Jenkins controller, and Jenkins agent helpers, native and
helper procedures, role evidence, and simulation role gates with the v1
fresh-state lifecycle contract.

This step follows accepted Step 13a reusable simulation lifecycle behavior and
repairs the role-local contract before shared integration consumes
role-readiness handoffs. Implement it role by role in dependency order. Step
13c shared integration, Step 14 boundary checks, and Step 15 final acceptance
depend on its accepted handoffs.

## Authorities And Required Reading

Read these before implementation:

- `docs/product/prd.md` for the initial-only v1 product boundary.
- `docs/contracts/lifecycle-contract.md` for identity and application-state
  classification, completion binding, and validation behavior.
- `docs/contracts/operator-execution-contract.md` for native/helper parity.
- `docs/contracts/account-model.md` and
  `docs/contracts/directory-model.md` for identities, homes, ownership, and
  protected state.
- `docs/contracts/artifact-bundle-contract.md` and
  `docs/contracts/validation-and-evidence.md` for staged inputs and evidence
  binding.
- `simulation/docs/shared/checkpoint-acceptance-protocol.md` for role-result acceptance
  and harness publication.
- `docs/operations/native/review-guide.md` for the role-manual review profile.

The authorities own product behavior. This step owns implementation sequence,
milestone boundaries, focused verification, and acceptance criteria only. It
defines the role completion postconditions consumed by the acceptance protocol;
it does not define or publish the simulation workflow head.

## Public Lifecycle Contract

Apply the same state classification to all three role helpers:

- `preflight` is non-mutating and classifies runtime identity separately from
  installed application/configuration state.
- Fully absent identity and application state is ready for initial setup.
- A fully matching runtime group, account, and empty canonical product home may
  be adopted for initial setup.
- An exact completion record bound to reviewed inputs, artifact digests,
  target identity, mode, selected run/state, and implementation revision
  returns `already-complete` without target mutation.
- Partial, conflicting, changed, or unbound state fails clearly before
  mutation. Helpers do not delete or reset it and do not reinstall,
  reconfigure, migrate, repair, or rotate it.
- Role validation is observational and requires the exact completed setup
  handoff. It does not start, restart, enable, rewrite, or repair service or
  application state.

The only resumable mutation boundary remains the later target-deployment
Gerrit external-review wait. Role-local phases do not gain a partial resume
model.

## Milestone Sequence

Implement the milestones in order. Each role milestone establishes a complete
handoff before the next consumer is aligned.

| Milestone | Scope | Dependency |
| --- | --- | --- |
| M1 | Shared state authority and marker semantics | Refined lifecycle authorities |
| M2 | Gerrit role lifecycle | M1 shared semantics |
| M3 | Jenkins controller role lifecycle | M2 Gerrit handoff contract |
| M4 | Jenkins agent role lifecycle | M3 controller handoff contract |
| M5 | Role gates, evidence, and Docker/VM acceptance | M2-M4 role implementations |

## M1: Shared State Authority And Marker Semantics

Implementation:

- Define one shared state classifier or equivalent common contract used by the
  three helpers without merging role-owned setup logic.
- Inspect account, group, canonical home, role-owned application paths,
  configuration, service definitions, runtime data, and completion records
  before mutation.
- Define the completion binding schema for reviewed env values, staged
  artifact manifest and payload digests, target identity, verification mode,
  selected run/state identity, helper revision, and completed checkpoint.
- Make `already-complete` a distinct successful no-op result and prove that it
  performs no service, filesystem, account, or application mutation.
- Reject legacy, marker-only, partial, changed, or otherwise unbound state.
  Do not add compatibility fallbacks or implicit cleanup.

Focused tests:

- Add a shared role-state classification test covering absent, adoptable
  identity/empty-home, exact complete, partial, conflicting, changed, and
  unbound state.
- Add a completion-binding test that changes each binding input independently.
- Add a no-mutation comparison for `already-complete`.

Acceptance:

- Every role consumes the same state vocabulary and completion-binding rules.
- State is classified before the first target mutation.
- Existing installed state can never enter the initial setup path merely
  because its OS identity matches.

## M2: Gerrit Role Lifecycle

Implementation:

- Replace site reset and reinstall behavior in `scripts/gerrit-setup.sh` with
  the M1 classifier and initial-only install/configure transitions.
- Permit only absent state or a matching identity with an empty Gerrit home to
  enter initial installation.
- Bind install and configuration completion to the verified WAR, rendered
  configuration, reviewed identity, endpoints, LDAP inputs, mode, target, and
  selected state.
- Return `already-complete` without stopping, starting, or rewriting Gerrit
  when the exact role handoff is complete.
- Keep Gerrit validation observational and update native/helper procedures and
  role evidence with the implemented behavior.

Focused tests:

- Gerrit fresh-state and empty-home adoption tests.
- Gerrit existing-site rejection and exact no-op rerun tests.
- Gerrit service/filesystem no-mutation validation tests.

Acceptance:

- Gerrit setup never deletes or resets an existing site.
- Fresh initial setup and exact no-op rerun produce a role-readiness handoff
  bound to the same reviewed state.

## M3: Jenkins Controller Role Lifecycle

Implementation:

- Replace controller stop, managed-directory deletion, and reinstall behavior
  in `scripts/jenkins-controller-setup.sh` with the M1 classifier and
  initial-only transitions.
- Permit only absent state or a matching identity with an empty Jenkins home
  to enter initial installation.
- Bind completion to the verified WAR and plugin closure, JCasC and service
  configuration, reviewed identity, endpoints, LDAP inputs, mode, target, and
  selected state.
- Return `already-complete` without stopping, starting, or rewriting Jenkins
  when the exact role handoff is complete.
- Keep controller validation observational and update native/helper procedures
  and role evidence with the implemented behavior.

Focused tests:

- Controller fresh-state and empty-home adoption tests.
- Controller existing-home rejection and exact no-op rerun tests.
- Controller service/filesystem no-mutation validation tests.

Acceptance:

- Controller setup never kills Jenkins or deletes a managed runtime/config
  directory to make installation succeed.
- Fresh initial setup and exact no-op rerun produce a controller-readiness
  handoff bound to the same reviewed state.

## M4: Jenkins Agent Role Lifecycle

Implementation:

- Replace managed-state reset behavior in
  `scripts/jenkins-agent-setup.sh` with the M1 classifier and initial-only
  transitions.
- Permit only absent state or a matching identity with an empty canonical home
  to enter initial setup; keep site-owned global SSH listener state outside the
  role-owned application-state classification.
- Bind completion to staged inputs, the account-scoped SSH policy, reviewed
  identity and endpoint, mode, target, and selected state.
- Return `already-complete` without rewriting the SSH policy, reloading SSH,
  or changing the runtime filesystem when the exact handoff is complete.
- Keep agent validation observational and update native/helper procedures and
  role evidence with the implemented behavior.

Focused tests:

- Agent fresh-state and empty-home adoption tests.
- Agent existing-role-policy/runtime rejection and exact no-op rerun tests.
- Agent SSH/filesystem no-mutation validation tests.

Acceptance:

- Agent setup never resets existing role-owned state or treats site-owned SSH
  listener state as authorization to reconfigure the role.
- Fresh initial setup and exact no-op rerun produce an agent-readiness handoff
  bound to the same reviewed state.

## M5: Role Gates, Evidence, And Runtime Acceptance

Implementation:

- Align Docker and VM role gates, phase summaries, completion-record consumers,
  reboot checks, and composite orchestration with the M1-M4 handoffs.
- Publish accepted role results through the shared workflow ledger and remove
  harness-only role progression markers without dual old/new readers.
- Record state classification, completion binding, `already-complete`, and
  blocked conflicts without storing secrets or manufacturing success.
- Update setup manuals, native references, simulations, and focused contract
  tests alongside the final implemented behavior.
- Preserve explicit Docker/VM cleanup commands and fresh run identities as the
  only simulation recovery path.

Verification order:

1. Run each role's focused shell and documentation tests, `bash -n`, and
   `git diff --check` after its milestone.
2. Run role phases individually in Docker from a newly generated run ID, then
   the composite role workflow.
3. Run role phases individually in VM simulation from a fresh
   `HARNESS_RUN_ID` and, when needed, a fresh `HARNESS_SET_ID`; remote VM
   mutation requires explicit approval for the selected target.
4. Run native target-like acceptance only with explicit approval for the
   selected hosts and actions.

Acceptance:

- All three role gates distinguish fresh, exact complete, and blocked existing
  state consistently.
- Fresh Docker and approved VM runs pass without implicit repair or cleanup.
- Exact role reruns are proven non-mutating, and changed bindings fail closed.
- The three accepted role-readiness handoffs are suitable inputs to Step 13c.

## State And Recovery Rules

- Do not add backward-compatibility guards for old role markers or generated
  state.
- Inspect stale state read-only, then use documented explicit cleanup and a
  fresh selected run/state identity.
- Never repair remote targets, VMs, containers, Jenkins, Gerrit, or SSH state
  without explicit approval for that target and action.

## Commit And Completion Strategy

Use one logical commit per accepted milestone. Each role milestone includes
the owning helper, focused regression tests, directly affected consumer docs,
and bounded verification. Do not combine remote runtime evidence or the
execution ledger with implementation commits.

Step 13b is complete only after M1-M5 pass their gates and fresh Docker plus
approved VM evidence confirms the role contract. Older successful role runs
remain diagnostic evidence for the previous implementation and do not satisfy
this step.
