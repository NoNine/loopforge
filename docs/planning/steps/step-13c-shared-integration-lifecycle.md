## Step 13c: Align Shared Integration Lifecycle

Align `scripts/integration-setup.sh`, the native and helper integration
procedures, integration evidence, and both simulation backends with the shared
integration contracts refined in commit `049636e`.

This is a cross-role implementation step. It follows accepted Step 13b
fresh-state role handoffs and the Step 13 M8 discovery work, but it is not
VM-specific. Step 13 integration acceptance, Step 14 boundary checks, and Step
15 final acceptance depend on this step.

This docs-first revision defines the intended checkpoint-result capture,
verification, and run-step contract. Runtime migration to `run-plan-state.env`, `run-steps/`,
`open-run-step`, and `commit-run-step` remains pending in M5.

## Authorities And Required Reading

Read these before implementation:

- `docs/contracts/lifecycle-contract.md` for checkpoint and mutation boundaries.
- `docs/contracts/gerrit-trigger-integration.md` for mode-specific ACL
  realization, credential custody, state binding, proof, and failures.
- `docs/contracts/validation-and-evidence.md` for checkpoint evidence and
  reviewed-input binding.
- `simulation/docs/shared/run-plan-transition-protocol.md` for integration
  result capture, verification, and run-step commitment.
- `docs/contracts/account-model.md` and `docs/contracts/directory-model.md` for
  accounts, shared storage, protected paths, ownership, and file modes.
- `docs/architecture/system-model.md` for interfaces and cross-role ownership.
- `docs/operations/native/review-guide.md` for the integration review profile.

The authorities own product behavior. This step owns implementation sequence,
milestone boundaries, focused verification, and acceptance criteria only.
It defines integration-owned setup, validation, and proof postconditions plus
the target-only review wait; it does not publish the simulation run-plan head.

## Public Command Contract

Retain the existing integration helper commands:

- `configure-integration`
- `validate-integration`
- `prove-integration`
- `collect-evidence`

Required behavior changes:

- `configure-integration --dry-run` performs complete non-mutating preflight
  and reports the mode-appropriate ACL plan.
- `configure-integration` owns ACL realization and shared setup. In
  `target-deployment`, it records both Gerrit reviews and returns non-success
  `blocked` without a setup-success marker until both are submitted and
  effective. In simulation, it directly applies and validates the ACLs without
  review creation or a wait.
- `validate-integration` is observational and does not require `--yes`.
- `prove-integration` requires matching validation state and never invokes
  validation implicitly.
- `collect-evidence` may collect partial diagnostic records but must not promote
  an incomplete checkpoint set to pass.
- Owning `collect-evidence` commands emit structured results for their
  phase. The global `scripts/collect-evidence.sh` collector runs only after
  end-to-end proof as the final Evidence audit input; it does not authorize
  target work or accept its own checkpoint.
- Helper-assisted `target-deployment` uses the human
  `docs/operations/setup/acceptance-checklist.md` for checkpoint decisions.
  Structured helper results support those decisions but do not
  replace them.

Loopforge v1 does not provide credential rotation. Normal configuration must
fail clearly when existing credential state requires replacement. Cleanup,
migration, and rotation are site-owned administration outside the Loopforge v1
helper and native setup surfaces.

## Milestone Sequence

Implement the milestones in order. A later milestone must not hide, replay, or
repair an earlier milestone failure.

| Milestone | Scope | Dependency |
| --- | --- | --- |
| M1 | Integration state, preflight, and Gerrit ACL realization | Accepted Step 13b M5 run-plan head and all three role handoffs |
| M2 | Jenkins controller and agent SSH custody | M1 bound integration state and effective ACLs |
| M3 | Shared storage, node, and Gerrit Trigger setup | M1 effective ACLs, M2 SSH custody, and role handoffs |
| M4 | Observational validation and active proof | M3 shared-setup completion; validation precedes proof |
| M5 | Run-plan ledger cutover, composite completion, and evidence alignment | M1-M4 bound outputs, accepted Step 13a run planner, and Step 13b role tail |
| M6 | Docker, VM, and native runtime acceptance | M5 focused tests pass |

## Integration Correlation And Cutover

Step 13c is intentionally sequential because each milestone creates state that
the next milestone consumes:

| Source milestone | Required output | Consumer |
| --- | --- | --- |
| Step 13b M5 | Three bound role handoffs and run-plan head at the end of the role tail | M1 preflight and M5 composite continuation |
| M1 | Bound integration state and mode-appropriate effective Gerrit ACLs | M2 credential/SSH custody and M3 Gerrit Trigger setup |
| M2 | Bound Jenkins-to-Gerrit and Jenkins-to-agent SSH custody | M3 node, credential, and trigger setup |
| M3 | Shared-setup completion covering storage, node, credentials, and trigger | M4 observational validation |
| M4 | Bound validation evidence followed by active proof evidence | M5 harness verification and evidence audit |
| M5 | Run-plan head through evidence audit and completed backend-local run plans | M6 Docker/VM composite runtime acceptance |

M1-M4 create structured checkpoint results without publishing composite-owned
state. M5 is one fail-closed harness cutover after every result contract exists; it
removes old progression markers instead of maintaining dual readers.

## M1: State, Preflight, And Gerrit ACL Realization

Implementation:

- Validate all four reviewed env files, three role-readiness handoffs, target
  SSH inventories, administrator access, selected state, mode, and ACL workflow
  before any mutation.
- Reject unsupported `target-deployment`, review, REST, or Gerrit-version
  behavior before creating accounts, tokens, keys, reviews, credentials, nodes,
  storage, or trigger state.
- Bind private state markers to reviewed inputs, target identities, mode,
  run/selected state, implementation revision, and mode-appropriate ACL state.
- Replace the constant evidence fingerprint with a real redacted binding.
- From fresh integration state, create the Gerrit integration service account
  and group. On the bound external-review resume, validate only the account and
  group recorded by that wait state.
- For target deployment, implement one `All-Projects` review for `Verified` and
  `streamEvents` and one target-project review for scoped read and voting.
- In target deployment, stop at the approval boundary and resume only with the
  same inputs and review IDs. In Docker and VM simulation, use only explicitly
  selected `simulation-only direct Gerrit REST apply`, validate effective
  global and project/ref permissions, and do not create reviews or wait.
- Do not create or rotate the Gerrit token or register integration keys before
  mode-appropriate effective access is proven.

Focused tests:

- `tests/integration-preflight-mutation-boundary-test.sh`
- `tests/integration-reviewed-acl-workflow-test.sh`
- `tests/integration-state-binding-test.sh`

Acceptance:

- Unsupported behavior fails before target mutation.
- Target deployment records two real reviews and reports `blocked` without a
  setup-success marker.
- Changed inputs or stale/unbound markers cannot resume the review wait.
- Simulation records Reviewed Access as `not-applicable` and proves the same
  effective permissions without claiming review activity.

## M2: Jenkins Controller And Agent SSH Custody

Implementation:

- Require absent controller-held Jenkins-to-Gerrit and Jenkins-to-agent key
  state before shared setup, then create both keypairs under the documented
  protected integration paths.
- Partial, conflicting, malformed, changed, or unbound key state fails clearly.
- Register the Gerrit public key without duplicating it or changing unrelated
  account keys.
- Append the agent public key only when absent. Never truncate
  `authorized_keys` or remove unrelated keys.
- Remove integration-owned deletion of agent `remoting.jar`, remoting
  directories, workspaces, or other role-owned runtime state.
- Establish reviewed known-hosts entries for Gerrit and the agent without
  `StrictHostKeyChecking=no` or unreviewed `ssh-keyscan` trust.
- Create Jenkins credentials without removing working credentials first.
- Treat existing state that requires credential replacement as conflicting
  state. It blocks and requires site-owned action or fresh selected state.
- Align the Gerrit, Jenkins controller, and Jenkins agent integration procedure
  sections as their owning behavior changes.

Focused tests:

- `tests/integration-key-custody-test.sh`
- `tests/integration-agent-authorization-test.sh`
- `tests/integration-known-hosts-test.sh`
- `tests/integration-nondestructive-rerun-test.sh`

Acceptance:

- Both SSH paths authenticate with strict reviewed host-key checking.
- Private keys remain on the Jenkins controller and only public keys cross role
  boundaries.
- An exact completed-state invocation returns `already-complete` and does not
  remove or rewrite keys, credentials, nodes, or role-owned agent state.

## M3: Shared Storage, Node, And Gerrit Trigger Setup

Implementation:

- Validate the exact shared group name and GID on both Jenkins hosts; create
  only fully absent state and reject collisions or mismatches.
- Configure the Jenkins-agent-hosted NFS export, controller mount, setgid group
  write, persistent configuration, reviewed client scope, and `root_squash`.
- Record one setup-owned controller-write/agent-read proof without storing
  credentials, scripts, or unrelated build artifacts in shared storage.
- Register the Jenkins SSH node after agent authorization and known-hosts state
  are ready. Preserve zero executors on the built-in controller node.
- Generate the initial absent Gerrit token only after effective ACL state is
  effective, then configure the Jenkins Gerrit credential and Gerrit Trigger.
- Fail instead of deleting and recreating an existing token ID during normal
  setup.
- Write the shared-setup structured result only after keys, public-key authorization,
  credentials, shared storage, node, and trigger configuration all succeed for
  the same bound inputs.

Focused tests:

- `tests/integration-shared-storage-contract-test.sh`
- `tests/integration-node-configuration-test.sh`
- `tests/integration-trigger-configuration-test.sh`
- `tests/integration-configure-phase-order-test.sh`

Acceptance:

- `configure-integration` completes from fresh selected state without hidden
  cleanup, implicit rotation, validation claims, or disposable proof artifacts.
- Shared storage source, mount, ownership, GID, mode, export options, and setup
  proof match the reviewed inputs.
- A passing setup result is absent after any partial failure.

## M4: Observational Validation And Active Proof

Implementation:

- Remove mutation confirmation and target-directory initialization from
  `validate-integration`.
- Validate mode-appropriate effective ACLs, both read-only SSH paths, key
  custody, storage/export/mount configuration, node configuration and online
  state, and Gerrit Trigger connection.
- Consume the M3 storage proof without writing another validation file.
- Do not create or replace credentials, nodes, jobs, builds, changes, events,
  votes, directories, or service state during validation.
- Bind validation output to the matching M3 structured result and reviewed inputs.
- Make `prove-integration` create one labeled disposable Jenkins job and one
  disposable Gerrit change. Use that change to prove SSH event delivery, agent
  scheduling and execution, REST `Verified +1`, and final Gerrit review state.
- Keep credential, event-stream, ACL, storage, node, scheduling, execution,
  vote, and review-state failures separately classified.

Focused tests:

- `tests/integration-validation-observational-test.sh`
- `tests/integration-proof-marker-binding-test.sh`
- `tests/integration-single-change-proof-test.sh`
- Existing voteable-label and Docker integration wiring tests.

Acceptance:

- A filesystem and service-state comparison shows validation changed no target
  or application state beyond bounded local logs, evidence, and status.
- Proof refuses missing or mismatched validation state and does not run
  validation implicitly.
- One disposable change proves event delivery, agent execution, REST voting,
  and Gerrit review state.

## M5: Run-Plan Ledger Cutover, Composite Completion, And Evidence Alignment

Implementation:

- Emit target-only reviewed-access evidence plus shared-setup, validation, and
  proof records. Simulation records Reviewed Access as `not-applicable` within
  shared-setup evidence.
- Record mode-appropriate ACL realization, effective checks and review fields,
  input binding, target/run identity, safe identifiers, results, bounded logs,
  and redaction state.
- Make `collect-evidence` validate the checkpoint set reached and reject
  contradictory success/failure signals without manufacturing missing success.
- Keep per-checkpoint structured results distinct from the final global Evidence
  audit. In simulation, commit `evidence-audit` only after the collector result
  has been revalidated by the harness; in helper-assisted target deployment,
  record the human decision in the acceptance checklist.
- Make both harnesses capture and verify integration checkpoint results and use
  `open-run-step` and `commit-run-step` for integration preflight, setup,
  validation, proof, and evidence audit.
- Remove the Docker validate marker and VM integration status markers plus
  every old reader. Exact run-step predecessors replace their progression role;
  structured checkpoint results remain distinct inputs to harness verification.
- Extend the backend-local run plans from the Step 13b role tail
  through integration preflight, setup, validation, proof, and evidence audit.
  Align summaries, exact resume, and `already-complete` with the run-plan head
  without adding another orchestration model, dual readers, or fallback paths.
- Update native and helper manuals alongside the final implemented command
  behavior. Do not document unavailable behavior as accepted runtime support.

Focused tests:

- Extend `tests/simulation-lifecycle-state-library-test.sh` for open/commit,
  hash-chain, exact-predecessor, interrupted activity, and orphan-record cases.
- Replace marker expectations in
  `tests/docker-harness-integration-wiring-test.sh` and
  `tests/vm-harness-integration-lifecycle-test.sh` with run-plan-head checks.
- Update `tests/docker-harness-run-workflow-test.sh` and add
  `tests/vm-harness-run-workflow-test.sh` for exact resume, first-failure
  propagation, intentional `status`, and completed-run behavior through the
  integration tail.
- Prove legacy validation/proof markers are rejected rather than consumed.

Acceptance:

- Evidence audit rejects stale, incomplete, unbound, or contradictory state.
- Only the run step chain authorizes integration progression.
- Evidence summaries report checkpoint outcomes and do not claim committed
  run-plan progress without a run-step record or target acceptance without the
  target acceptance checklist.
- No harness validation or proof-prerequisite marker remains in either backend.
- Docker and VM capture and verify the same helper-owned structured results with the same
  predecessor and proof rules.
- Both backend planners reach `already-complete` only after the evidence-audit
  checkpoint and never publish composite-owned run-plan state.

## M6: Docker, VM, And Native Runtime Acceptance

Verification order:

1. Run focused shell and documentation tests plus `bash -n` and
   `git diff --check`.
2. Run Docker integration phases individually from a newly generated run ID,
   then run the composite Docker workflow.
3. Run VM integration phases individually from a newly generated run ID and,
   when resource identity is suspect, a fresh `HARNESS_SET_ID`; then run the
   composite VM workflow on an explicitly approved remote KVM target.
4. Run native target-like acceptance only with explicit approval for the
   selected hosts and actions.

Acceptance:

- Fresh Docker and VM runs pass configure, validate, prove, and composite
  workflows through explicitly selected and labeled direct REST ACL apply.
- Native acceptance remains separate and cannot be claimed from simulation.

## State And Recovery Rules

- Do not add compatibility fallbacks for old generated integration state.
- Replace marker-only integration state with bound structured checkpoint results, remove
  harness-only validation/proof progression markers when the
  run-plan ledger lands, and do not read old and new progression state together.
- Inspect stale state read-only, then use documented explicit cleanup and a
  fresh run/state identity.
- Docker recovery uses `stop`, `restore-baseline`, and `clean` before
  `init-run` generates a new run ID for the selected Docker project.
- VM recovery follows the retained env file and documented `stop`,
  `restore-baseline`, `clean`, or `destroy` boundaries. Host-wide libvirt
  cleanup requires the documented dry run and explicit approval.
- Never repair remote targets, VMs, containers, Jenkins, or Gerrit without
  explicit approval for that target and action.

## Commit And Completion Strategy

Use one logical commit per accepted milestone. Each commit includes the owning
implementation, focused regression tests, and directly affected consumer docs.
Do not combine remote runtime evidence or execution-ledger state with the
implementation commit.

Prior Step 13 M8 runs remain diagnostic evidence for the old implementation.
They do not satisfy Step 13c or final integration acceptance. Step 13c is
complete only after M1-M6 pass their gates and fresh Docker and approved VM
runtime evidence confirms the refined contract.
