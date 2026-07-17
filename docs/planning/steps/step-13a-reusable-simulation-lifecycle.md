# Step 13a: Align Reusable Simulation Lifecycle

Implement the shared `create`, `start`, `stop`, `restore-baseline`, `clean`,
and `destroy` lifecycle for Docker and VM simulation before role setup is
aligned with fresh-state semantics.

This step owns implementation sequence, not product authority. Read the
lifecycle, directory, evidence, and simulation contracts before changing the
harnesses. Step 13b role lifecycle, Step 13c shared integration, Step 14, and
Step 15 depend on this step.

## Authorities And Required Reading

- `docs/contracts/lifecycle-contract.md` for resource transitions, start/stop
  behavior, run identity, and recovery boundaries.
- `docs/contracts/directory-model.md` for baseline and retained-output custody.
- `docs/contracts/validation-and-evidence.md` for immutable run binding.
- `simulation/README.md` for shared command semantics.
- `simulation/docker/README.md` and `simulation/vm/README.md` for backend
  realization.
- `simulation/docs/harness-design.md` and
  `simulation/docs/lifecycle-state-model.md` for shared architecture and exact
  state guards.
- `simulation/vm/docs/implementation-design.md` and
  `simulation/vm/docs/sequences.md` for VM implementation boundaries.

## Public Command Contract

Both backends expose:

- `create`: establish or verify the reusable simulation set and clean baseline,
  leaving the set stopped.
- `start`: start baseline prerequisites or exact completed services without
  setup mutation.
- `stop`: gracefully stop services and preserve durable state.
- `restore-baseline`: reset stopped durable runtime state only.
- `clean`: preserve retained output and remove mutable active-run state only.
- `destroy`: remove ownership-validated reusable resources and baseline state.

Remove `up` and `down` from help, dispatch, docs, tests, and composite workflow
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

Implement the exact schemas, classifiers, and guards from
`simulation/docs/lifecycle-state-model.md`; this plan records dependency order
rather than redefining them.

- Validate the canonical 1-24 character `HARNESS_SET_ID` before path or backend
  mutation. Derive `loopforge-docker-<set-id>` and
  `loopforge-vm-<set-id>` directly, and use ownership-checked versioned hashes
  only for backend names with tighter limits.
- Put the nonblocking set lock at
  `generated/simulation/<backend>/locks/<set-id>.lock`, outside the deletable
  set root. Mutations take it exclusively; state inspection takes it shared.
- Keep `active-run.env` set-scoped and authoritative for claim/reset gating.
  Keep `workflow-state.env` run-scoped and authoritative only for checkpoint
  activity and progression. Parse both with strict fixed-key readers, never
  shell `source`.
- Publish the complete run root, marker, and initial workflow state before the
  active pointer. Publish checkpoint `mutating` state before target mutation,
  then immutable hash-linked completion and the idle workflow head. Publish
  restoration evidence before the reset gate. Remove the active pointer last
  during cleanup.
- Preserve the immutable run marker and checkpoint records through `clean`.
  Remove only known mutable run paths; an interrupted cleanup remains
  retryable under the strict active pointer, immutable marker, and restoration
  evidence even when earlier cleanup targets are already absent.
- Centralize `baseline`, `exact-bound`, `active-incomplete`, and `conflicting`
  classification in shared state code. Role and integration implementations
  provide checkpoint postconditions in Steps 13b and 13c.

## Milestone Sequence

| Milestone | Scope | Dependency |
| --- | --- | --- |
| M1 | Shared identity, lock, active-run, workflow-record, and classifier primitives | Refined authorities |
| M2 | Simulation source/effective input lifecycle and start-owned target access | M1 |
| M3 | Docker create/start/stop state machine | M2 |
| M4 | Docker baseline capture and restore | M3 |
| M5 | VM start/stop migration, active-run binding, and effective-input adoption | M2 |
| M6 | Cleanup, evidence, composite workflows, and acceptance | M3-M5 |

## M1: Shared Identity, Lock, Records, And Classifier

Implementation:

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
- Add immutable hash-linked checkpoint records and atomic same-directory
  publication helpers. Establish `idle`, `observing`, `mutating`, and `waiting`
  activity without implementing Step 13b/13c checkpoint postconditions yet.
- Add the shared durable classifier. Treat an open target mutation as
  `active-incomplete`, record/fingerprint/order disagreement as `conflicting`,
  and allow restart only from `baseline` or `exact-bound`.
- Derive and validate the Docker Compose project name and VM libvirt resource
  prefix from `HARNESS_SET_ID`; neither namespace may depend on the run ID.
- Preserve the active-run pointer across `stop` and `start`; allow another
  `init-run` only after matching baseline restoration and `clean` clear it.
- Include the run ID in bounded log metadata and all evidence records.

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
- `run` workflow ordering with `start` and no implicit recovery commands.

Acceptance:

- Every checkpoint can prove its exact immutable run and simulation-set IDs.
- Restart preserves both IDs; reset and cleanup require a different run ID.
- The same set ID resolves to the same backend namespace across runs.

## M2: Simulation Input Lifecycle And Start-Owned Access

Implementation:

- Replace the simulation meaning of reviewed helper inputs with explicit source
  templates, stable effective inputs, and ephemeral live target access. Keep
  target-deployment reviewed-input behavior unchanged.
- Make `init-run` snapshot selected harness, role, and integration templates
  under private `host/source-inputs/`, bind `source_inputs_fingerprint` in the
  immutable run marker, and publish workflow state with effective inputs
  pending. Helpers must never consume source snapshots directly.
- Add the strict `host/state/effective-inputs.env` binding and
  `input_state=pending|ready` workflow transition. Bind the backend, set, run,
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
- Require every workflow phase to reject pending, missing, changed, partially
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
  or workflow execution.
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

Implementation:

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
  idempotent success hide incomplete or conflicting workflow state.

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

Implementation:

- Capture a clean pre-setup Docker baseline during `create`: image and Compose
  digests, clean LDAP data, empty product homes with numeric ownership, empty
  shared storage, and target SSH identity.
- Store the checksummed manifest and archives under the selected Docker
  simulation-set root without including credentials or application setup state.
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

## M5: VM Start/Stop Migration And Effective-Input Adoption

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
- Apply the same existing-create, already-running start, already-stopped stop,
  coherent status, and already-absent destroy outcomes as Docker. Remove
  name-derived deletion when full ownership metadata is unavailable.
- Adopt the M2 source/effective input records, first-start publication, exact
  role env transfer, and per-start DHCP/SSH refresh without adding a second VM
  input model.

Focused tests:

- Updated VM lifecycle, terminal-summary, docs, and run-workflow tests.
- Same-set new-run tests after stop/restore/clean.
- Same-run stop/start tests and cross-run evidence/marker rejection tests.

Acceptance:

- VM `start`/`stop` retain current runtime semantics and pass existing resource
  ownership and baseline gates with active-run binding added.

## M6: Cleanup, Evidence, Composite Workflows, And Acceptance

Implementation:

- Require stopped selected simulation sets for `clean`, `restore-baseline`, and
  `destroy` where the backend contract requires it.
- Record `restored-pending-clean` only after successful baseline restoration.
  While that gate is active, block `start`, `init-run`, repeated restoration,
  and every workflow phase; permit only the documented read-only commands,
  `clean`, and `destroy`.
- Make `clean` preserve the immutable run marker, checkpoint records, and
  retained output under the old run root, remove only known mutable active-run
  state, and remove the set pointer last while preserving baseline resources.
- Make Docker and VM `run` state-aware. Fresh absent state initializes,
  creates, and starts; an unclaimed retained baseline initializes and verifies
  existing `create`; an exact active run resumes at its next required phase;
  an exact completed run is made running and returns `already-complete`.
- When run ID is omitted for a claimed set, resolve the active pointer and print
  `mode=resume`. Block explicit run-ID mismatch, changed input fingerprints,
  interrupted/partial/conflicting state, and `restored-pending-clean`.
- Keep `run` free of stop, restore, clean, destroy, or audit calls and leave the
  selected set running.
- Make `status` succeed for coherent absent, unclaimed, stopped, and running
  states and fail nonzero with `conflicting` for contradictory state. Make
  `destroy` return `already-absent` only for a fully absent unclaimed set.
- Update help, examples, terminal-output docs, cleanup tools, tests, and
  repository guardrails in the same accepted command migration.
- Emit baseline, reusable-set, and immutable run evidence without secrets or
  verbose logs.

Verification order:

1. Focused shell tests and `bash -n` after each milestone.
2. Shared and backend documentation contracts plus `git diff --check`.
3. Docker lifecycle phases from baseline through stop/start and full reset.
4. VM lifecycle phases on an explicitly approved remote KVM target.
5. Fresh Docker and approved VM composite runs using newly generated run IDs
   on the same reusable sets after successful baseline reset and cleanup.

Focused tests:

- Both backends reject `start`, `init-run`, workflow phases, and repeated
  restoration from `restored-pending-clean`.
- Failed restoration cannot authorize `clean` or release active-run ownership.
- Successful `clean` transitions the restored set to baseline-stopped and
  unclaimed while retaining immutable review output.
- Fresh, retained-baseline, exact-resume, stopped-resume, completed,
  run-ID-mismatch, changed-input, interrupted, and conflicting `run` cases.
- Cross-backend idempotent `create`, `start`, `stop`, `status`, and `destroy`
  cases with identical shared meanings.

Acceptance:

- Docker and VM expose the same lifecycle names and state meanings.
- Both backends prove restart without setup mutation.
- Both backends prove baseline reset and new-run isolation.
- `up` and `down` are absent from supported command surfaces.

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
lifecycle, Docker lifecycle, Docker baseline restore, VM migration, and
cross-backend acceptance independently reviewable. Do not include
execution-ledger state in implementation commits.

Step 13a is complete only after M1-M6 pass and fresh Docker plus approved VM
runtime evidence proves lifecycle parity and immutable run isolation.
