# Step 13a: Align Reusable Simulation Lifecycle

Implement the shared `create`, `start`, `stop`, `restore-baseline`, `clean`,
and `destroy` lifecycle for Docker and VM simulation before role setup is
aligned with fresh-state semantics.

This step owns implementation sequence, not product authority. Read the
lifecycle, directory, evidence, and simulation contracts before changing the
harnesses. Step 13b role lifecycle, Step 13c shared integration, Step 14, and
Step 15 depend on this step.

The accepted M1-M4 implementation forms the historical baseline. It
established the current shared identity/input foundation plus Docker
reusable-resource and baseline behavior under the earlier combined
workflow-state model. The refined contract does not rewrite that history.

This docs-first revision defines a post-M4 run-plan and operation-record
cutover. M5-M9 own that implementation sequence; current generated state must
not be represented as already using the new names or transitions.

Simulation input selection and OS dependency preparation are waived product
checkpoints in this plan. They belong to the `init-run` and initial `create`
operation records respectively, and the simulation run plan begins at Artifact
preparation.

## Authorities And Required Reading

- `docs/contracts/lifecycle-contract.md` for resource transitions, start/stop
  behavior, run identity, and recovery boundaries.
- `docs/contracts/directory-model.md` for baseline and retained-output custody.
- `docs/contracts/validation-and-evidence.md` for immutable run binding.
- `simulation/docs/shared/simulation-model.md` for shared command semantics.
- `simulation/docs/docker/docker-simulation.md` and
  `simulation/docs/vm/vm-simulation.md` for backend realization.
- `simulation/docs/shared/harness-design.md` and
  `simulation/docs/shared/lifecycle-state-model.md` for shared architecture and exact
  state guards.
- `simulation/docs/shared/run-plan-transition-protocol.md` for capturing and
  verifying role/integration checkpoint results and committing their run steps.
- `simulation/docs/shared/operation-records.md` for resource-lifecycle records.
- `simulation/docs/docker/implementation-design.md` for Docker-local module
  boundaries and dependency direction.
- `simulation/docs/vm/implementation-design.md` and
  `simulation/docs/vm/command-sequences.md` for VM implementation boundaries.

## Public Command Contract

Both backends expose:

- `run`: classify selected state and compose the same first-class command
  handlers available for granular invocation without directly publishing
  lifecycle or run-plan state.
- `create`: establish or verify the reusable simulation set and clean baseline,
  leaving the set stopped.
- `start`: start baseline prerequisites or exact completed services without
  setup mutation.
- `status`: report coherent selected state without mutation or run-plan
  progression.
- `stop`: gracefully stop services and preserve durable state.
- `restore-baseline`: reset stopped durable runtime state only.
- `clean`: preserve retained output and remove mutable active-run state only.
- `destroy`: remove ownership-validated reusable resources and baseline state.

Remove `up` and `down` from help, dispatch, docs, tests, and composite run-plan
without compatibility aliases.

## State And Identity Contract

- Keep `HARNESS_RUN_ID` as the immutable identity of exactly one setup and
  validation attempt. Generate it inside `init-run` when the operator omits it;
  reject an explicitly supplied value whose canonical run root already exists.
- Bind runtime inputs, phase markers, completion markers, evidence, terminal
  summaries, and status to that run ID.
- Use `HARNESS_SET_ID` as the shared reusable simulation-set identity for both
  backends, defaulting to `default` when omitted. Each selected set owns one
  non-secret `active-run.env` pointer.
- Treat the Docker Compose project name and VM libvirt resource prefix as
  derived backend metadata. Derive them only from the backend and set ID, keep
  them stable across runs, and never include `HARNESS_RUN_ID`.
- Reject `init-run` while the selected reusable set has an active run.
- Preserve the same run ID and pointer across `stop -> start`.
- Clear the pointer and mutable run state only after successful
  `stop -> restore-baseline -> clean`; retained review output remains under the
  immutable old run root.
- Do not allow an older run to satisfy any prerequisite of a newer one.

## Approved Implementation Decisions

For M5-M9, implement the exact schemas, classifiers, and guards from
`simulation/docs/shared/lifecycle-state-model.md`; this plan records dependency order
rather than redefining them. Implement the generic run-step transitions plus
the harness-side checkpoint-result capture and verification boundary from
`simulation/docs/shared/run-plan-transition-protocol.md`; do not synthesize the
structured results delivered by Steps 13b and 13c.

- Validate the canonical 1-24 character `HARNESS_SET_ID` before path or backend
  mutation. Derive `loopforge-docker-<set-id>` and
  `loopforge-vm-<set-id>` directly, and use ownership-checked versioned hashes
  only for backend names with tighter limits.
- Put the nonblocking set lock at
  `generated/simulation/<backend>/locks/<set-id>.lock`, outside the deletable
  set root. Mutations take it exclusively; state inspection takes it shared.
- Keep `active-run.env` set-scoped and authoritative for claim/reset gating.
  Keep `run-plan-state.env` run-scoped and authoritative only for run-step
  activity and progression. Parse both with strict fixed-key readers, never
  shell `source`.
- Publish the complete run root, marker, and initial run-plan state before the
  active pointer. Publish run-step `mutating` state before target mutation,
  then immutable hash-linked completion and the idle run-plan head. Publish the
  restoration operation record before the reset gate. Remove the active
  pointer last during cleanup.
- Preserve the immutable run marker, run-step records, and operation records
  through `clean`.
  Remove only known mutable run paths; an interrupted cleanup remains
  retryable under the strict active pointer, immutable marker, and restoration
  operation record even when earlier cleanup targets are already absent.
- Centralize `baseline`, `exact-bound`, `active-incomplete`, and `conflicting`
  classification in shared state code. Role and integration implementations
  provide checkpoint postconditions in Steps 13b and 13c.
- Keep the initial run-plan head empty through `init-run`, `create`, and
  `start`. These commands publish only their owning simulation state and
  operation records; the first run step is `prepare-artifacts-gerrit`.

## Milestone Sequence

| Milestone | Scope | Dependency |
| --- | --- | --- |
| M1 | Shared identity, lock, active-run, combined workflow record, and classifier primitives | Refined authorities at the accepted baseline |
| M2 | Simulation source/effective input lifecycle and start-owned target access | M1 |
| M3 | Docker create/start/stop state machine | M2 |
| M4 | Docker baseline capture and restore | M3 |
| M5 | Shared `R`/`P`/`C` state and record cutover with Docker as the reference backend | M1-M4 baseline and refined authorities |
| M6 | VM reusable-set lifecycle and effective-input parity on the refined state model | M5 |
| M7 | Cross-backend reset, cleanup, status, and operation-record alignment | M5-M6 |
| M8 | First-class command convergence and state-aware `run` planning | M7 |
| M9 | Reusable lifecycle acceptance and downstream handoff | M7-M8 |

## Accepted M1-M4 Baseline And Post-M4 Contract Delta

The accepted M1-M4 contract produced the current runtime baseline:

- canonical set/run identity, stable locks, `active-run.env`, strict
  `workflow-state.env`, checkpoint-chain mechanics, and durable
  classification;
- source snapshots, start-published effective inputs, and current target-access
  refresh;
- retained Docker containers, network, images, bind state, and runtime-only
  start/stop behavior; and
- checksummed Docker baseline capture and ownership-validated restoration with
  restoration evidence and a reset gate.

The refined authorities introduce a post-M4 contract delta. M5-M9 must replace,
not reinterpret, the accepted generated schema:

- resource lifecycle state `R` owns presence, power, and the reset gate;
- product run-plan state `P` owns only the committed run-step head and open
  activity;
- coordination state `C` owns the active-run claim, effective-input readiness,
  and derived durable-content classification;
- simulation input selection and OS dependency preparation remain operation
  outcomes of `init-run` and initial `create`, not product run steps;
- `run-plan-state.env`, `run-steps/`, operation records, and
  `restore_operation_record_sha256` replace the corresponding combined
  workflow/checkpoint/restoration-evidence schema; and
- retained-baseline reuse becomes `init-run -> start`; only an absent set needs
  `create` before `start`.

Do not rewrite M1-M4 history to imply that this cutover already exists. Do not
add old/new dual readers, compatibility aliases, or fallback classification.
Tests that need the refined schema must construct fresh state; operators
recover existing generated state through the documented explicit restore,
clean, destroy, or fresh-set procedures.

## Downstream Correlation And Handoff

The remaining milestones separate reusable lifecycle completion from the
run-plan tails that depend on later owning-layer postconditions:

| Source milestone | Handoff | Consumer |
| --- | --- | --- |
| Step 13a M7 | Complete Docker/VM lifecycle, reset, status, and operation-record semantics | Step 13a M8 command planning and Step 13b runtime fixtures |
| Step 13a M8 | Backend-local `run` planners that reuse first-class handlers and select the next run step without publishing one directly | Step 13b M5 role run-plan tail and Step 13c M5 integration/evidence tail |
| Step 13a M9 | Accepted reusable lifecycle and immutable run isolation | Step 13b role implementation |
| Step 13b M5 | Captured and verified role checkpoint results and run-plan head through the role checkpoint families | Step 13c integration preflight and composite completion |
| Step 13c M5 | Integration and evidence-audit tail attached to the accepted planner | Step 13c M6 full composite runtime acceptance |

Step 13a does not complete a full product run plan. Step 13b proves individual
role phases and their composite plan segment. Step 13c is the first step that
can complete end-to-end `run`, because only then do all owning role, integration,
proof, and evidence results exist.

## M1: Shared Identity, Lock, Records, And Classifier

Accepted implementation baseline:

- Replace shared `up`/`down` parsing and summaries with `start`/`stop`.
- Replace Docker's public `HARNESS_PROJECT_NAME` identity and VM's public
  `LOOPFORGE_VM_SET_ID` identity with `HARNESS_SET_ID` across bootstrap inputs,
  rendered/runtime config, markers, summaries, and evidence. Do not retain
  aliases or old-field readers.
- Add the shared set-ID grammar and direct backend namespace derivations. Add a
  versioned hash helper for length-limited names and require full ownership
  verification before using a hashed resource.
- Generate a collision-resistant `HARNESS_RUN_ID` during `init-run` when the
  operator omits it. Permit an explicit ID only when its canonical run root
  does not exist.
- Add shared immutable run-marker readers and binding checks without backend
  dispatch abstraction or compatibility handling for old markers.
- Add the stable set lock and acquire it nonblocking in every state-reading or
  mutating command with the approved shared/exclusive mode. Keep `run` locking
  at each internal command boundary.
- Add one strict non-secret `active-run.env` pointer under the selected
  simulation set and one strict run-scoped `workflow-state.env`. Make
  `init-run` fail when either record, its referenced run, or other prior state
  is malformed.
- Add immutable hash-linked workflow checkpoint records and atomic same-directory
  publication helpers. Establish `idle`, `observing`, and `mutating` activity
  without implementing Step 13b/13c product postconditions yet.
- Remove harness-only validation-pass and proof-prerequisite markers when the
  run-step chain replaces them. Retain backend resource and baseline ownership
  records, and do not add dual old/new progression readers.
- Add the shared durable classifier. Treat an open target mutation as
  `active-incomplete`, record/fingerprint/order disagreement as `conflicting`,
  and allow restart only from `baseline` or `exact-bound`.
- Derive and validate the Docker Compose project name and VM libvirt resource
  prefix from `HARNESS_SET_ID`; neither namespace may depend on the run ID.
- Preserve the active-run pointer across `stop` and `start`; allow another
  `init-run` only after matching baseline restoration and `clean` clear it.
- Include the run ID in bounded log metadata and all structured checkpoint results.

Focused tests:

- Shared command-surface rejection for `up` and `down`.
- Automatic and explicit run-ID creation, collision, stale-pointer, and
  cross-run binding tests.
- Shared set-ID parsing, old-identity rejection, stable derived-namespace, and
  cross-set isolation tests.
- Lock contention, shared-reader, pointer-publication ordering, strict parser,
  malformed/duplicate field, interrupted initialization, and interrupted
  cleanup tests.
- Workflow transaction, hash-chain, open-mutation, unknown-checkpoint,
  predecessor-order, exact-bound, and conflicting-state classifier tests.
- Same-run `stop -> start` tests and reset/clean new-run tests.
- `run` plan ordering with `start` and no implicit recovery commands.

Acceptance:

- Every checkpoint can prove its exact immutable run and simulation-set IDs.
- Restart preserves both IDs; reset and cleanup require a different run ID.
- The same set ID resolves to the same backend namespace across runs.

## M2: Simulation Input Lifecycle And Start-Owned Access

Accepted implementation baseline:

- Replace the simulation meaning of reviewed helper inputs with explicit source
  templates, stable effective inputs, and ephemeral live target access. Keep
  target-deployment reviewed-input behavior unchanged.
- Make `init-run` snapshot selected harness, role, and integration templates
  under private `host/source-inputs/`, bind `source_inputs_fingerprint` in the
  immutable run marker, and publish workflow state with effective inputs
  pending. Helpers must never consume source snapshots directly.
- Add the strict `host/state/effective-inputs.env` binding and
  `input_state=pending|ready` workflow-state transition. Bind the backend, set, run,
  run marker, source fingerprint, and `effective_inputs_fingerprint` without
  compatibility readers for the superseded simulation schema.
- Make the first successful `start` verify selected resource ownership and
  target access, render the complete stable role and integration env bundle in
  private staging, atomically publish `host/runtime-inputs/` and its binding,
  transition workflow state to ready, and only then report success.
- Make repeated `start` verify byte-identical effective inputs and refresh only
  current backend transport access. It must not rerender stable values. `stop`
  preserves both input bindings while making live access unavailable.
- Treat Docker published target access and VM DHCP/SSH readiness as backend
  observations owned by `start`. Keep backend-assigned transport hosts outside
  source and effective fingerprints and do not add a persistent execution
  context or general backend identity fingerprint.
- Remove VM per-phase role env rendering. Transfer the exact published role env
  to bundle-factory and target helper paths for preparation, configuration, and
  validation.
- Remove retained VM `host/rendered/integration-inputs/`. For simulation
  integration only, copy the immutable effective `integration.env` to a private
  temporary file, overlay only
  `INTEGRATION_GERRIT_TARGET_SSH_HOST`,
  `INTEGRATION_JENKINS_CONTROLLER_TARGET_SSH_HOST`, and
  `INTEGRATION_JENKINS_AGENT_TARGET_SSH_HOST`, invoke the unchanged shared
  helper env-file interface, and delete the file after invocation.
- Require every product run-plan phase to reject pending, missing, changed, partially
  published, or cross-run effective inputs before helper or target mutation.
  `audit-state` remains read-only and reports source/effective binding failures.
- Update shared and backend summaries so `start: ok` means resources, target
  access, and stable effective inputs are ready without exposing the internal
  publication steps as another public command.

Focused tests:

- Source template snapshot, source fingerprint, and no-effective-inputs-before-
  start tests for both backends.
- First-start atomic publication, pointer/run binding, ready-last ordering, and
  interrupted-publication rejection tests.
- Repeated-start byte-identity tests proving no stable env rewrite.
- Stop/start tests with changed ephemeral transport hosts but unchanged owned
  resources and SSH identity.
- Ownership or SSH identity drift tests that block before effective publication
  or run-plan execution.
- Role helper tests proving the exact fingerprinted effective env is transferred
  without a later renderer.
- Integration adapter tests proving only the three target SSH host fields may
  differ, the shared helper interface is unchanged, and the temporary file is
  removed on success and failure.
- Cross-run, pending-input, source/effective fingerprint mismatch, malformed
  strict record, and unknown-field rejection tests.

Acceptance:

- `init-run` claims source-bound run state without claiming effective helper
  readiness.
- The first successful `start` publishes one stable effective bundle and every
  later `start` preserves it while refreshing live target access.
- Role and integration helpers never consume unbound or per-phase-rerendered
  stable inputs.
- DHCP and equivalent ephemeral transport changes do not invalidate an exact
  run when selected ownership and SSH identity still agree.

## M3: Docker Create, Start, And Stop

Accepted implementation baseline:

- Extend Docker `create` to build pinned project images, create retained
  stopped containers and network, initialize prerequisites as needed, and
  leave the simulation set stopped.
- Make repeated `create` on the exact stopped selected set verify set-scoped
  metadata and return `state=existing` without mutation. Block running,
  unclaimed, restored-pending-clean, partial, drifted, unowned, or mismatched
  state.
- Move reusable baseline, active-run, and durable bind state under
  `generated/simulation/docker/sets/<set-id>/`; keep immutable
  attempt output under `generated/simulation/docker/<run-id>/`.
- Make `start` use only the selected retained containers. Reject missing,
  recreated, drifted, running-conflict, or unowned resources.
- From clean baseline state, start SSH and LDAP prerequisites only. From exact
  completed state, start Gerrit and Jenkins through runtime-only operations.
- Add runtime-only start/stop primitives that never call install or configure.
- Make `stop` gracefully stop Gerrit and Jenkins before Compose stop and prove
  the same container IDs and writable layers remain.
- Make exact repeated `start` and ownership-valid repeated `stop` return
  `state=already-running` and `state=already-stopped` respectively. Never let
  idempotent success hide incomplete or conflicting run-plan state.

Focused tests:

- Docker create-leaves-stopped and exact-container start tests.
- Docker existing-create, running-create rejection, already-running start, and
  already-stopped stop tests.
- Baseline-state start versus completed-state service start tests.
- Graceful stop ordering and writable-layer preservation tests.

Acceptance:

- `start -> stop -> start` preserves exact configured state and restores
  readiness without setup mutation.
- Ordinary start/stop never calls Compose down or recreates containers.

## M4: Docker Baseline Capture And Restore

Accepted implementation baseline:

- Capture a clean pre-setup Docker baseline during `create`: image and Compose
  digests, clean LDAP data, empty product homes with numeric ownership, empty
  shared storage, and target SSH identity.
- Store the checksummed manifest and archives under the selected Docker
  simulation-set root without real credentials or post-baseline application
  setup state. Clean LDAP archives may retain documented simulation-only fake
  credential state because it is required to restore the directory service.
- Require stopped, ownership-validated selected containers before restore.
- Recreate containers only inside `restore-baseline`, then restore only the
  selected bind data using numeric ownership and metadata-preserving tooling.
- Verify the restored baseline and leave containers stopped.
- Reject image, Compose, archive, ownership, SSH identity, or baseline binding
  drift. Do not repair or recapture a mismatched baseline.

Focused tests:

- Baseline manifest and sensitive-content exclusion tests.
- Running-state rejection and selected-resource ownership tests.
- Container recreation, bind restoration, and unrelated-resource preservation
  tests.

Acceptance:

- Restored Docker state is equivalent to the recorded clean baseline and ready
  for a new run ID after `clean` and `init-run`.

## M5: Shared State And Docker Reference Cutover

Implementation:

- Separate state ownership in `simulation/lib/state.sh` without requiring
  three generic modules: resource state `R`, product run-plan state `P`, and
  derived coordination state `C` must have distinct readers, validation, and
  transition helpers.
- Replace `workflow-state.env`, `checkpoints/`, `active_checkpoint`,
  `last_checkpoint`, and restoration-evidence field names with the documented
  run-plan, run-step, and operation-record schema. Remove old readers and
  writers in the same cutover.
- Keep `init-run`, `create`, `start`, `stop`, `restore-baseline`, `clean`, and
  `destroy` outside product run-step commitment. `init-run` writes an empty
  product run plan plus its operation record; initial `create` writes resource,
  OS dependency, and baseline proof only in its operation record.
- Preserve the artifact-first product vocabulary. The first allowed run step
  is `prepare-artifacts-gerrit`; simulation has no input-selection, OS
  dependency, or Reviewed Access run step.
- Make `start` publish effective inputs in `C` without advancing `P`. Make
  `restore-baseline` update `R` and the reset gate without rewinding or
  advancing `P`.
- Adapt Docker state, paths, lifecycle orchestration, audit, summaries, and
  evidence consumers to the refined shared contract before changing VM.
- Reject pre-cutover generated records and mixed old/new state. Recovery uses
  explicit cleanup or a fresh selected set; no compatibility path is added.

Focused tests:

- Extend `tests/simulation-lifecycle-state-library-test.sh` for separate
  `R`/`P`/`C` ownership, strict new schemas, artifact-first ordering, and
  operation records that cannot supply a run-step checkpoint-result digest.
- Update init-run, Docker bootstrap, input-publication, create, start/stop,
  baseline, restore, clean, audit, and generated-layout tests to use only the
  new paths and fields.
- Prove `init-run`, resource commands, restore, and clean never call or emulate
  `commit-run-step`.
- Prove stale `workflow-state.env`, checkpoint directories, old restoration
  fields, and mixed schemas fail clearly rather than being adopted.

Acceptance:

- Docker exposes separate `R` and `P` progression with `C` used only for
  cross-machine guards.
- Resource operation records and product checkpoint results/run-step records cannot
  substitute for one another.
- Existing M1-M4 identity, locking, input, retained-container, start/stop, and
  baseline behavior remains valid under fresh refined state.

## M6: VM Reusable-Set And Input Parity

Implementation:

- Rename VM public dispatch, internal lifecycle entrypoints, summaries,
  evidence commands, sequence docs, and focused fixtures from `up`/`down` to
  `start`/`stop`.
- Keep existing graceful shutdown, hard-stop fallback, snapshot restore, and
  ownership validation behavior unchanged.
- Store the simulation set's non-secret `active-run.env` pointer under
  `generated/simulation/vm/sets/<set-id>/` and bind VM run markers,
  runtime inputs, status, evidence, integration markers, reboot evidence, and
  cleanup to its immutable run ID.
- Reject removed command names and old unbound markers.
- Apply the same existing-create, already-running start, and already-stopped
  stop outcomes as Docker. Preserve exact VM resources across `stop -> start`
  and remove name-derived mutation when full ownership metadata is unavailable.
- Adopt the M2 source/effective input records, first-start publication, exact
  role env transfer, and per-start DHCP/SSH refresh without adding a second VM
  input model.

Focused tests:

- Updated VM create/start/stop, terminal-summary, documentation, active-run,
  and effective-input tests.
- Same-run stop/start tests with stable effective inputs and refreshed live
  DHCP/SSH access.
- Cross-run input, evidence, marker, and selected-resource rejection tests.

Acceptance:

- VM `create`, `start`, and `stop` retain their backend behavior while exposing
  the same `R`/`P`/`C` state meanings and record ownership as Docker.
- The VM set, active run, source/effective inputs, and live target access remain
  separately bound across stop/start.
- No VM reader or writer retains the superseded combined workflow schema.

## M7: Cross-Backend Reset, Cleanup, Status, And Operation Records

Implementation:

- Require stopped selected simulation sets for `clean`, `restore-baseline`, and
  `destroy` where the backend contract requires it.
- Record `restored-pending-clean` only after successful baseline restoration.
  While that gate is active, block `start`, `init-run`, repeated restoration,
  and every product run-plan phase; permit only the documented read-only
  commands, `clean`, and `destroy`.
- Make `clean` preserve the immutable run marker, run-step records, operation
  records, and retained output under the old run root, remove only known
  mutable active-run state, and remove the set pointer last while preserving
  baseline resources.
- Make `status` succeed for coherent absent, unclaimed, stopped, and running
  states and fail nonzero with `conflicting` for contradictory state. Make
  `destroy` return `already-absent` only for a fully absent unclaimed set.
- Finish VM restore, clean, destroy, audit, and retained-output behavior against
  the same shared guards already applied to Docker.
- Emit create, start, stop, restoration, cleanup, and destruction operation
  records without secrets or verbose logs. Bind the reset gate to the matching
  restore operation record.
- Update help, examples, terminal-output docs, cleanup tools, and repository
  guardrails for the accepted lifecycle surface.

Focused tests:

- Both backends reject `start`, `init-run`, product run-plan phases, and repeated
  restoration from `restored-pending-clean`.
- Failed restoration cannot authorize `clean` or release active-run ownership.
- Restore and clean preserve the old committed `P` head and immutable run-step
  chain; neither command opens or commits a product run step.
- Successful `clean` transitions the restored set to baseline-stopped and
  unclaimed while retaining immutable review output.
- Cross-backend idempotent `create`, `start`, `stop`, `status`, and `destroy`
  cases with identical shared meanings.
- Same-set new-run tests after exact `stop -> restore-baseline -> clean`, with
  old run output retained and rejected as a new prerequisite. Prove the new
  run uses `init-run -> start` without calling `create`.

Acceptance:

- Docker and VM expose the same lifecycle names and state meanings.
- Both backends prove restart without setup mutation.
- Both backends prove baseline reset and new-run isolation.
- `up` and `down` are absent from supported command surfaces.

## M8: First-Class Command Convergence And State-Aware Run Planning

Implementation:

- Keep `run` and every granular phase as first-class public commands. Direct
  invocation and composite selection must converge on the same backend-local
  `*_cmd_<phase>` handler before capability delegation.
- Keep the `run` handler state-passive: it resolves selected identity, reads and
  classifies state, constructs the allowed command plan, invokes handlers, and
  prints a summary. It does not write the active-run pointer, run-plan head,
  run-step record, completion marker, or backend state directly.
- Make Docker and VM select the shared plans for fresh absent, retained
  baseline, exact resumable, stopped resumable, already-running completed, and
  stopped completed state. Include `status` as the intentional user-facing
  observation after conditional `start` or before resume/completion output.
- Select `init-run -> start -> status` for an unclaimed retained baseline.
  Reserve `create` for an absent set or explicit direct verification; do not
  insert it after restore and clean.
- Select `preflight -> init-run -> create -> start -> status` for an absent
  set. Both fresh plans enter product execution at
  `prepare-artifacts-gerrit`.
- When `HARNESS_RUN_ID` is omitted for a claimed set, resolve the active pointer
  and report `mode=resume`. Block explicit run-ID mismatch, changed input
  fingerprints, `active-incomplete`, `conflicting`, and
  `restored-pending-clean` before later mutation.
- Acquire and release the normal shared or exclusive set lock at every selected
  command boundary; do not hold one lock across the composite.
- Stop at the first nonzero handler result. Never invoke `stop`,
  `restore-baseline`, `clean`, `destroy`, `audit-state`, or VM `reboot` from a
  run plan, and never perform rollback or repair.
- Dispatch checkpoint families in the shared order, but defer harness
  capture, verification, and run-step commitment for role checkpoint results to Step 13b
  M5 and integration checkpoint results to Step
  13c M5. Step 13a tests orchestration with focused handlers and fixtures; it
  does not claim the downstream product run plan passes.

Focused tests:

- Both backends cover fresh, retained-baseline, exact-resume, stopped-resume,
  completed-running, completed-stopped, run-ID-mismatch, changed-input,
  active-incomplete, and conflicting plan selection.
- Command-trace tests prove retained-baseline planning never invokes `create`,
  absent-resource planning invokes it exactly once, and neither branch treats
  a resource operation as product progression.
- Direct and composite invocation reach the same command handler, lock mode,
  summary contract, and failure result for every shared command family.
- `status` appears in every executable plan at the documented observation
  boundary and never advances the run-plan ledger.
- A failed handler prevents every later handler, and no recovery or
  backend-only command appears in any selected plan.
- Run-level before/after state comparison proves that only invoked command
  handlers, not the run planner itself, publish durable changes.

Acceptance:

- Docker and VM implement the same public command shape without a shared
  backend dispatcher or cross-backend shell API.
- Every state change observed during `run` is owned by an invoked first-class
  command handler.
- Exact plan selection is ready to consume Step 13b role results and Step 13c
  integration/evidence results without another orchestration model.

## M9: Reusable Lifecycle Acceptance And Downstream Handoff

Verification order:

1. Run focused shell and documentation tests plus `bash -n` and
   `git diff --check` after M5-M8.
2. Run Docker lifecycle commands individually from fresh state through
   stop/start, baseline restoration, cleanup, and a new run identity.
3. Run the same VM lifecycle commands on an explicitly approved remote KVM
   target, using a fresh set when retained resource identity is suspect.
4. Exercise every `run` plan branch with bounded local fixtures or command
   stubs that prove handler selection, locking, status, and failure propagation
   without claiming role or integration runtime success.

Acceptance:

- Fresh Docker and approved VM evidence proves lifecycle parity, restart
  preservation, baseline reset, and immutable run isolation.
- Focused orchestration evidence proves both backends are ready for the Step
  13b role run-plan tail.
- Full Docker and VM composite runtime acceptance remains deferred to Step 13c
  M6 after role, integration, proof, and evidence-audit checkpoint results are
  verified and their run steps committed.

## State And Recovery Rules

- Do not add compatibility aliases, old-marker readers, or stale-state
  fallbacks.
- Recovery commands validate exact ownership and selected baseline before
  mutation.
- Host-wide cleanup remains separate and never substitutes for selected
  baseline restoration.
- Remote VM mutation requires explicit approval for the selected target and
  action.

## Commit And Completion Strategy

Use one logical commit per accepted milestone. Keep shared primitives, input
lifecycle, Docker lifecycle, Docker baseline restore, VM parity, cross-backend
cleanup, run planning, and reusable lifecycle acceptance independently
reviewable. Do not include execution-ledger state in implementation commits.

Step 13a is complete only after M1-M9 pass. Fresh Docker plus approved VM
runtime evidence must prove reusable lifecycle parity and immutable run
isolation; focused orchestration evidence must prove the downstream handoff
without claiming full composite run-plan success.
