# Simulation Run-Plan Transition Protocol

## Purpose And Authority

This document owns how Docker and VM harnesses verify product-owner producer
records and commit product run-plan transitions. It defines producer ownership,
execution binding, run-step verification, publication order, and failure
handling.

`simulation/docs/shared/lifecycle-state-model.md` owns the run-plan ledger
schema, run-step vocabulary and order, command guards, classifications, and
transition effects. This protocol invokes `open-run-step` and
`commit-run-step`; it does not add states, run-step identifiers, or transition
effects. Product checkpoint semantics remain in
`docs/contracts/lifecycle-contract.md`, producer content and redaction remain
in `docs/contracts/validation-and-evidence.md`, and simulation operation
records remain in `simulation/docs/shared/operation-records.md`.

Native and helper-assisted `target-deployment` do not use the simulation run
plan. Their product owners may still write producer records, while the human
operator or reviewer records acceptance through the applicable target
deployment checklist.

## Record Ownership

| Record | Semantic owner | Meaning |
| --- | --- | --- |
| Producer record | Product checkpoint owner | Bound product outcome and redacted supporting proof for one checkpoint attempt |
| Run-step record | Active backend harness under the set lock | Immutable history that the harness verified the producer and committed the corresponding run-plan transition |
| Simulation operation record | Simulation lifecycle operation owner | Outcome and proof for resource lifecycle work outside the product run plan |

Only the run-plan head and its hash-linked run-step chain determine which
product step the simulation may invoke next. A producer record, run-step file,
operation record, exit status, or terminal summary does not change that state
by existing. The `commit-run-step` transition changes the head and writes the
authoritative run-step record atomically.

## Run-Plan Producer Requirements

| Product checkpoint family | Required producer record |
| --- | --- |
| Artifact preparation | Bound manifest, checksums, payload digests, source boundary, and verification outcome from the corresponding role helper |
| Artifact staging | Bound target-side manifest and checksum-verification outcome from the simulation staging utility |
| Role-local setup | Bound setup outcome and proof from the corresponding role helper |
| Role-local validation | Bound observations against the completed setup state and current live role state |
| Integration preflight | Bound observations against the three role-readiness handoffs, product inputs, inventory, access, and mode support |
| Shared integration setup | Bound setup outcome and proof, including effective `simulation-only direct Gerrit REST apply` results |
| Cross-role validation | Bound observations against the completed shared setup and current live integration state |
| End-to-end trigger verification | Bound outcome and proof for the declared disposable workflow and final Gerrit result |
| Evidence audit | Collector producer record that validates, but does not create, the required producer-record set |

The harness supplies one opaque execution-binding fingerprint to the product
owner. The producer record repeats that fingerprint without learning Docker,
libvirt, set-lock, predecessor, or run-plan details. The harness verifies the
exact producer record and places its digest in the run-step record's
`producer_record_sha256`.

The run-step record separately binds backend, set, run, source and effective
input fingerprints, baseline state, step identifier, predecessor, activity
kind, producer digest, and timestamps. Every run step requires published
effective inputs and an exact baseline fingerprint.

## Simulation Input And Dependency Waivers

Simulation does not create producer or run-step records for Input review or
source selection or for OS dependency provisioning. `init-run` owns simulation
source selection and records it as an operation. Initial `create` owns
simulation resource creation, OS dependency preparation, and baseline capture
and records them as one operation. These waivers are simulation-only and do not
alter target-deployment product checkpoints.

## Transition Protocol

The active backend harness performs one run-plan attempt under the selected set
lock:

1. Verify the active run, exact predecessor, state classification, and
   step-specific prerequisites.
2. Complete every check that can fail before the owning product operation.
3. Invoke `open-run-step` with the declared activity. For product mutation,
   publish it immediately before the first mutation; for observation, publish
   it immediately before invoking the observer.
4. Invoke only the utility that owns the product checkpoint instance. It writes
   one bound producer record after completing its checks; a successful mutating
   producer writes that record last.
5. Verify the producer outcome, opaque execution binding, referenced
   postcondition, target identity, safe product bindings, and bounded logs
   without repair.
6. Construct the immutable run-step record and invoke `commit-run-step`.

A failure before step 6 does not advance the run-plan head. An unreferenced
run-step file cannot advance the plan.

## Input, Baseline, And Restore

`init-run` creates the selected run state and snapshots simulation source
inputs. For an absent set, `create` establishes resources, prepares the
simulation-owned OS dependency baseline, and captures the baseline. The
baseline manifest records the package and target state needed for later
verification; it is simulation set state, not a producer or run-step record.

For a later run against an existing exact baseline, `init-run` binds that
baseline directly and `start` publishes effective inputs. The run planner does
not call `create`, and the first product run step is Artifact preparation.

`restore-baseline` remains a simulation operation. It restores the selected
clean simulation baseline, writes a simulation operation record, and sets the
reset gate without modifying the old run-plan chain. After `clean`, `init-run`
creates a fresh run with an empty run-plan head; `start` then makes it ready for
Artifact preparation without another `create`.

## Final Evidence Audit

The global collector runs once at the end of the normal product run plan after
end-to-end trigger verification. It rejects a stale, mixed, incomplete,
malformed, secret-bearing, or contradictory producer-record set and writes the
Evidence audit producer record. The harness then verifies that record against
the exact `prove-integration` predecessor and commits the `evidence-audit` run
step. Only that transition makes the run plan complete.

An operator may run the collector earlier for partial diagnosis. A partial
package is not an Evidence audit producer record and cannot enter the successful
run-step chain.

## Failure Protocol

| Failure point | Record handling | Run-plan effect |
| --- | --- | --- |
| Prerequisite or precheck failure | Retain a bounded failed producer or operation record when useful | Do not call `open-run-step` |
| Failure after an observing open | Retain the failed producer record | Do not commit; the same observation may retry against the unchanged head |
| Failure after a mutating open | Retain the failed producer record and reject partial output | Do not commit; durable state remains `active-incomplete` until explicit recovery |
| Producer or postcondition mismatch | Treat the producer record as conflicting proof | Do not commit; the open activity remains |
| Producer-record write or validation failure | Treat the record as missing or invalid | Do not commit; the open activity remains |
| Run-step or head publication failure | Retain the producer record for diagnosis | The incomplete publication cannot authorize the next run step |

Failed producer records never enter the successful run-step chain. Read-only
audit may diagnose disagreement but cannot manufacture a missing transition.

## Simulation Integration

Simulation has no Reviewed Access product step, wait, or resume path. The
integration helper directly applies and validates the selected ACL realization,
writes one bound shared-setup producer record, and records Reviewed Access as
`not-applicable`. The harness verifies that record before committing the
`configure-integration` run step; it never synthesizes review activity.
