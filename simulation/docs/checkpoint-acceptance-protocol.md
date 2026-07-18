# Simulation Checkpoint Acceptance Protocol

## Purpose And Authority

This document owns how Docker and VM harnesses accept owning-layer results and
producer evidence before publishing simulation workflow progress. It defines
proof ownership, binding, verification, and publication order.

`simulation/docs/lifecycle-state-model.md` owns the ledger schemas, checkpoint
vocabulary and order, command guards, classifications, and transition effects.
This protocol invokes `open-checkpoint` and `commit-checkpoint`; it does not add
states, transitions, or checkpoint names. Product checkpoint semantics remain
in `docs/contracts/lifecycle-contract.md`, and evidence schemas and redaction
remain in `docs/contracts/validation-and-evidence.md`.

Native and helper-based `target-deployment` do not use the simulation ledger.
Their owning utilities still produce completion state and evidence, while the
actor and native acceptance checklist coordinate progression.

## Accepted Records

Do not use "checkpoint marker" as a generic name for these distinct records.

| Record | Semantic owner | Meaning |
| --- | --- | --- |
| Owning-layer result or completion record | Utility that owns the output or durable postcondition | The exact owned state satisfies its checkpoint contract |
| Evidence record | Utility that performed the operation or observation | Redacted proof of what was checked, with a bounded log reference |
| Workflow checkpoint record | Active backend harness under the set lock | The selected simulation run accepted the owned result and evidence in order |

Only the workflow head and its immutable checkpoint chain authorize simulation
progression. They do not replace owning-layer truth: before a later checkpoint
or exact restart, the harness revalidates the owned result required by the
current head. Evidence alone authorizes neither state nor progression.

## Acceptance Requirements

Simulation acceptance requires the selected mode, set, run, target identity,
effective inputs, producing utility revision, and completed checkpoint.
Applicable results also bind staged artifact digests, configuration
fingerprints, or ACL realization and effective permissions.

| Checkpoint scope | Required owned result |
| --- | --- |
| Artifact preparation | Manifest, checksums, payload digests, and source-boundary record from the corresponding role helper |
| Artifact staging | Target-side manifest and checksum result from the simulation artifact module |
| Role setup | Bound role completion record from the corresponding role helper |
| Role or integration observation | Producer evidence against the required prior owned results and current live state |
| Shared integration setup | Bound integration completion record, including effective `simulation-only direct Gerrit REST apply` results |
| End-to-end proof | Producer evidence for the declared disposable workflow and final Gerrit result |
| Evidence audit | Collector result that validates, but does not create, the required checkpoint set |

Producer evidence carries the same safe binding or a redacted fingerprint of
protected state. The harness verifies it and places its digest in the workflow
record's `evidence_sha256`. A basename, marker existence check, terminal
summary, or unbound `status=pass` is never sufficient.

## Publication Protocol

The active backend harness performs one checkpoint attempt under the selected
set lock:

1. Verify the active run, effective inputs, exact predecessor, state
   classification, and phase prerequisites.
2. Complete every check that can fail before the owning operation.
3. Invoke `open-checkpoint` with the declared activity. For target mutation,
   publish it immediately before the first mutation; for observation, publish
   it immediately before invoking the validator.
4. Invoke only the checkpoint-owning utility. A mutating utility writes its
   bound completion record last when the checkpoint creates durable owned
   state.
5. Require producer evidence with the owned-result binding and bounded log,
   preserving the producer record digest in any normalized harness copy.
6. Revalidate the owned result, evidence, identities, and input bindings without
   repair.
7. Construct the immutable workflow checkpoint record and invoke
   `commit-checkpoint`.

A utility exit code, owned result, evidence file, or terminal summary produced
before step 7 does not advance the workflow.

## Failure Protocol

| Failure point | Evidence handling | State-model transition |
| --- | --- | --- |
| Prerequisite or precheck failure | Retain bounded `blocked` or `fail` evidence when useful | Do not call `open-checkpoint` |
| Failure after an observing open | Retain producer failure evidence | Do not commit; the same observation may retry against the unchanged head |
| Failure after a mutating open | Retain bounded failure evidence; reject partial output | Do not commit; state remains `active-incomplete` until explicit recovery |
| Owned-result or evidence mismatch | Treat the result as conflicting evidence, not success | Do not commit; the open activity remains |
| Evidence write or validation failure | Treat evidence as missing or invalid | Do not commit; the open activity remains |
| Workflow record or head publication failure | Retain any owned result and evidence for diagnosis | The incomplete publication cannot authorize later work; audit reports the state-model result |

Failure evidence never enters the successful checkpoint chain. Read-only audit
may diagnose disagreement but cannot manufacture a missing commit.

## Simulation Integration

Simulation has no Reviewed Access checkpoint, activity, wait, or resume path.
The integration helper directly applies and validates the selected ACL
realization, writes one bound shared-setup completion record and producer
evidence, and records Reviewed Access as `not-applicable`. The harness accepts
those outputs before committing `configure-integration`; it never synthesizes
review activity.
