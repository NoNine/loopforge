# Simulation Operation Records

## Purpose And Authority

This document owns records produced by Docker and VM simulation resource
lifecycle operations. These records retain bounded proof for simulation state
transitions; they do not claim product checkpoints, enter the product run plan,
or represent human acceptance.

`simulation/docs/shared/lifecycle-state-model.md` owns state dimensions, guards,
and transition effects. `simulation/docs/shared/generated-state-layout.md` owns
record locations and retention. `docs/contracts/validation-and-evidence.md`
owns shared status, redaction, contradiction, and aggregation rules.

## Record Contract

Every simulation operation record includes:

- `record_kind=simulation-operation`.
- Backend and operation name.
- Timestamp and implementation revision.
- Status: `pass`, `fail`, or `blocked`.
- Set ID and run ID when the operation has that selected context.
- Safe resource, baseline, and input fingerprints applicable to the operation.
- Bounded log references.
- Redaction status.

It contains no product checkpoint family, product producer outcome, run-plan
predecessor, or human acceptance decision. It cannot supply
`producer_record_sha256` for a run-step record. The global evidence package may
include operation records as supplemental diagnostics, but they never satisfy
a required product checkpoint.

## Operation Mapping

| Simulation command or activity | Durable operation record |
| --- | --- |
| `preflight` | None by default; terminal result only |
| `init-run` resource/run-state publication | `init-run` operation record, including selected source templates and supported overrides under the simulation input-selection waiver |
| `create` resource and baseline lifecycle | `create` operation record, including simulation-owned OS dependency preparation and proof under the simulation provisioning waiver |
| `start` | `start` operation record |
| `reboot` | `reboot` operation record |
| `stop` | `stop` operation record |
| `restore-baseline` | `restore-baseline` operation record whose digest binds the reset gate |
| `clean` | `clean` operation record retained with review output |
| `destroy` | `destroy` operation record when a retained selected context exists |
| `status`, `audit-state`, `ssh` | None by default; read-only terminal or audit output only |
| Composite `run` | No composite operation record; invoked commands retain their own records |

## State Transition Relationship

The simulation operation changes state only after its owner validates the
operation outcome and atomically publishes the owning state transition. The
operation record documents that transition but does not cause it by existing.
An orphaned operation record has no state authority.

A failed operation may retain a `fail` or `blocked` record, but it must not
publish successful state. Restoration is the narrow exception that binds its
successful operation-record digest into `active-run.env` before exposing the
`restored-pending-clean` reset gate.
