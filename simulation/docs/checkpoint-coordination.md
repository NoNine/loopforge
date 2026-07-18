# Checkpoint State Coordination Design

## Purpose And Scope

This document defines how helper-owned completion state, machine-generated
evidence, and the simulation workflow checkpoint ledger coordinate without
becoming competing sources of workflow truth. It is the implementation design
companion for checkpoint work spanning Steps 13a, 13b, and 13c.

This document is subordinate to:

- `docs/contracts/lifecycle-contract.md` for checkpoint semantics, phase order,
  mutation boundaries, and rerun behavior;
- `docs/contracts/validation-and-evidence.md` for evidence schema, status, and
  redaction requirements;
- `docs/contracts/directory-model.md` for state custody and retained output;
- `simulation/docs/harness-design.md` for architectural planes; and
- `simulation/docs/lifecycle-state-model.md` for exact simulation state
  schemas, classification, command guards, and transitions.

This design applies the contracts to machine-orchestrated Docker and VM
simulation. Native `target-deployment` uses operator sequencing and the native
acceptance checklist instead of the simulation workflow ledger. Role and
integration helpers still own their target-local completion state and evidence
in every mode.

## State Categories

Use distinct names for the three state categories. Do not use "checkpoint
marker" as a generic name for all of them.

| Category | Meaning | Authority |
| --- | --- | --- |
| Owning-layer completion record | A bound claim that durable role or integration state satisfies its owned postcondition | The utility that owns the mutation and postcondition |
| Evidence record | Redacted audit proof of an attempted or completed check, including bounded log references | The utility that performed the check |
| Workflow checkpoint record | An immutable, hash-linked simulation record that advances one run through the ordered workflow | The active backend harness using the shared state protocol |

Terminal summaries, copied evidence, status output, and aggregated evidence are
derived views. They do not authorize a later phase.

## Ownership Model

Ownership follows the meaning of state, not the path where a copy is retained.

| State | Semantic owner | Writer or custodian | Authorized consumers |
| --- | --- | --- | --- |
| Prepared artifact postcondition | Corresponding role helper in `prepare-artifacts` scope | Bundle factory | Backend harness, staging phase, and reviewer |
| Staged artifact postcondition | Simulation artifact module or target-deployment transfer actor | Target staging plus retained checksum and manifest result | Role helper and reviewer |
| Gerrit role state and completion record | `scripts/gerrit-setup.sh` and the Gerrit service within their documented boundaries | Gerrit target | Backend harness and integration preflight |
| Jenkins controller role state and completion record | `scripts/jenkins-controller-setup.sh` and the Jenkins service within their documented boundaries | Jenkins controller target | Backend harness and integration preflight |
| Jenkins agent role state and completion record | `scripts/jenkins-agent-setup.sh` and the SSH service within their documented boundaries | Jenkins agent target | Backend harness and integration preflight |
| Reviewed-access wait and shared integration state | `scripts/integration-setup.sh` | Integration helper state and affected targets | Backend harness and later integration phases |
| Role evidence | Corresponding role helper | Helper evidence directory; harness may retain a verified copy | Harness, collector, and reviewer |
| Integration evidence | Integration helper | Integration evidence directory; harness may retain a verified copy | Harness, collector, and reviewer |
| Backend lifecycle evidence | Docker or VM harness | Run-scoped harness evidence directory | Collector and reviewer |
| Active-run pointer, workflow head, and checkpoint chain | Shared simulation lifecycle protocol | Active Docker or VM harness under the selected set lock | Later harness commands and read-only audit |
| Evidence aggregation | Global evidence collector | Collector output directory | Reviewer |

The global evidence collector validates and aggregates records. It does not
own the underlying runtime claim and cannot create missing success.

The shared state library owns record mechanics, strict parsing, ordering,
hash-chain validation, and classification. It does not know whether Gerrit,
Jenkins, SSH, or shared integration is correctly configured. The owning role or
integration utility defines those postconditions; the backend harness verifies
their bound result before publishing workflow progress.

## Source-Of-Truth Rules

Only `workflow-state.env` and its immutable checkpoint chain authorize
simulation workflow progression. A later phase must not advance because it
finds only a passing evidence file, target completion record, terminal summary,
or historical harness marker.

The ledger is not sufficient by itself to classify live target or retained
artifact state. Before a later phase or exact restart, the harness also verifies
the owning outputs, completion records, and postconditions required by the
current ledger head.
Disagreement between the ledger, completion state, inputs, selected identities,
or backend state is `conflicting`.

This produces two complementary truths:

- the owning output or completion record answers "does the exact owned state
  satisfy this checkpoint?"; and
- the workflow checkpoint chain answers "did this selected simulation run
  accept that result in the required order?"

Evidence answers neither question by itself. It answers "what was observed,
how was it bound, and where is the bounded proof?"

## Binding Between Records

Not every checkpoint produces a target completion record. Artifact preparation
uses its manifest, checksums, payload digests, and source-boundary record as the
owned postcondition. Artifact staging uses its target-side manifest and
checksum result. Observational checkpoints may produce evidence without a new
durable application completion record.

Role setup, shared integration setup, and the reviewed-access wait do require
owning-layer completion records because later commands must distinguish exact
completed application state from stale, partial, changed, or foreign state.
The owning Step 13b or 13c implementation defines its concrete private schema,
but the binding includes, as applicable:

- completed checkpoint and helper revision;
- mode and target identity;
- selected run or target-deployment state identity;
- reviewed or published effective input fingerprint;
- staged artifact manifest and payload digests;
- role or integration configuration fingerprint; and
- reviewed Gerrit change identifiers for the integration wait and setup.

The producer-owned evidence record includes the same safe output or completion
binding, or a redacted fingerprint of protected state. It records an owned
output or completion-record reference and digest when that can be exposed
without disclosing secrets. The immutable workflow checkpoint record binds the
accepted evidence through `evidence_sha256`, so the checkpoint chain indirectly
binds the verified owning-layer postcondition without copying product-specific
fields into the shared ledger schema.

A constant label, basename, marker existence check, or unbound `status=pass`
is not a completion binding.

## Workflow Transaction Protocol

### Successful Mutating Checkpoint

The active backend harness performs this sequence under the selected set lock:

1. Verify the active run, ready effective inputs, exact workflow predecessor,
   durable classification, and phase-specific prerequisites.
2. Run every check that can fail before mutation without publishing a mutation
   activity.
3. Immediately before the first target mutation, atomically publish
   `activity=mutating` and the active checkpoint.
4. Invoke the checkpoint-owning utility. That utility performs only its
   checkpoint work, produces its owned outputs, and writes a bound completion
   record last when the checkpoint creates durable application state.
5. Require producer-owned evidence with the safe output or completion binding
   and bounded log. A normalized harness copy must preserve the producer record
   digest and must not replace its semantic claim.
6. Verify the owned outputs or completion record, their input and identity
   binding, the evidence, and the checkpoint postconditions without repairing
   state.
7. Write the immutable workflow checkpoint record with the accepted evidence
   digest.
8. Atomically advance the workflow head and return it to `activity=idle` last.

A helper exit code, completion record, or evidence file produced before step 8
does not make the checkpoint complete. A crash after step 3 and before step 8
leaves `active-incomplete`.

### Successful Observational Checkpoint

The harness verifies the same run, inputs, predecessor, and required owning
outputs or completion records, then publishes `activity=observing`. The owning
validator observes live state without setup or repair, writes evidence, and
returns. The harness verifies the evidence, writes the immutable checkpoint
record, and advances the workflow head last.

An interrupted or failed observation does not classify unchanged durable
target content as incomplete, but the open observation blocks workflow
progression until the owning phase is explicitly retried against the unchanged
head and inputs.

### Reviewed Gerrit Access Wait

The integration helper owns the reviewed-access completion and wait binding.
The workflow ledger represents the sole supported resumable mutation boundary
as `activity=waiting`, bound to the same inputs, targets, predecessor, and two
Gerrit review identifiers. Only the owning integration phase may verify those
reviews and resume the wait. Review submission remains an external Gerrit
administrator action, not a harness mutation.

## Failure And Publication Rules

| Failure point | Evidence | Owned output or completion record | Workflow result |
| --- | --- | --- | --- |
| Preflight, before published mutation | Record `blocked` or `fail` when useful | Absent | Head unchanged and idle |
| Mutating phase after activity publication | Record bounded failure evidence | Partial output is not accepted; a completion record remains absent unless the full owning postcondition completed | `active-incomplete`; no checkpoint publication |
| Completion verification mismatch | Record `fail` or `blocked` | Existing record is conflicting evidence, not success | No checkpoint publication |
| Observational check failure | Record `fail` or `blocked` | Prior setup completion remains unchanged | No checkpoint publication; observation must be retried explicitly |
| Evidence write or validation failure | Missing or invalid | May exist | No checkpoint publication |
| Checkpoint-record or head publication failure | Passing evidence may exist | May exist | No later phase may proceed; audit reports incomplete or conflicting state |

Failure evidence is retained for diagnosis but is never inserted into the
successful checkpoint chain as a completed predecessor.

## Existing Marker Disposition

Classify historical markers by the contract they represent; do not preserve
all existing files behind compatibility readers.

### Retain And Strengthen

Retain a marker only when it represents independently necessary owning-layer
state, such as:

- exact role installation and configuration completion;
- exact shared integration setup completion; or
- the bound reviewed Gerrit access wait.

Replace marker-only or loosely bound formats with the Step 13b or 13c
completion-record schema. Reject old, partial, changed, or unbound records and
require explicit cleanup or migration outside the normal workflow.

### Remove Or Fold Into The Ledger

Remove harness-created files whose only meaning is that an orchestration phase
previously passed, including validation-pass and proof-prerequisite markers.
The immutable checkpoint chain becomes their single replacement. A backend may
retain backend resource and baseline ownership records because those classify
simulation infrastructure rather than workflow progression.

Do not make either the new ledger or owning utilities consult both old and new
phase markers. That would create two progression authorities and turn stale
state into a compatibility target.

## Mode Boundary

Docker and VM simulation use the durable workflow ledger because their backend
harnesses orchestrate a complete machine workflow. The same shared protocol
and checkpoint meanings apply to both backends even when transport and
infrastructure realization differ.

Helper-based and native `target-deployment` do not currently have a global
machine workflow ledger. Role and integration helpers still write their owned
completion state and evidence. The actor coordinates phases, and the native
acceptance checklist records corresponding outcomes. Simulation checkpoint
records must not be presented as target-deployment acceptance.

## Implementation Boundaries

- `simulation/lib/state.sh` owns generic ledger mechanics and must not inspect
  Gerrit-, Jenkins-, SSH-, or integration-specific state.
- Backend lifecycle modules own lock-scoped transaction orchestration and
  checkpoint publication, not target postcondition definitions.
- Role modules invoke role helpers and verify helper-owned completion outputs;
  they do not synthesize role success.
- Integration modules invoke the integration helper and verify its owned wait,
  setup, validation, and proof outputs; they do not synthesize cross-role
  success.
- Evidence modules serialize and validate records; they do not invoke lifecycle
  work or advance the workflow head.
- Terminal and status modules render derived state and never repair or promote
  it.

## Verification Requirements

Focused tests must prove:

- an owned output, completion record, or passing evidence alone cannot advance
  a checkpoint;
- a checkpoint cannot publish without matching passing evidence;
- cross-run, cross-set, changed-input, and out-of-order records fail closed;
- mutating activity is durable before the first target mutation;
- an interrupted mutation remains `active-incomplete`;
- observational failure does not mutate or repair target state;
- the reviewed-access wait resumes only through its owning phase;
- legacy harness pass markers are rejected after their replacement lands;
- old owning-layer marker formats are rejected rather than read as compatible;
- the collector cannot manufacture a missing checkpoint; and
- retained evidence from an older run cannot satisfy a new run.
