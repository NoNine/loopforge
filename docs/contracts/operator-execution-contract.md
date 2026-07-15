# Operator Execution Contract

## Purpose And Authority

This document owns the durable contract for how an operator executes
Loopforge role and integration work. It defines parity between the native OS
and application procedure and the reviewed-input helper procedure. Native
operation references are the direct procedural baseline; setup manuals own the
helper workflow that applies that baseline.

It does not own lifecycle phase semantics, role-specific command transcripts,
simulation backend mechanics, evidence schema, or mutable implementation
availability. Those belong respectively to `docs/contracts/lifecycle-contract.md`, the
role manuals and native operation references, simulation documentation,
`docs/contracts/validation-and-evidence.md`, and `project-state/execution-status.md`.

## Operator Interfaces

Target deployment supports two equivalent operator interfaces:

| Aspect | Native operator procedure | Reviewed-input helper procedure |
| --- | --- | --- |
| Execution | Operator performs documented OS and application operations through delegated privilege. | Reads reviewed inputs and performs idempotent target operations through delegated privilege. |
| Service lifecycle | Creates or updates the documented guest systemd units and uses standard systemd control. | Installs or updates the documented guest systemd units and uses standard systemd control. |
| Validation | Operator performs bounded observational checks and records the result in the native acceptance checklist; detailed logs remain target-owned. | Performs equivalent bounded observational checks and collects redacted evidence. |
| Scope boundary | Remains role-local until the shared integration workflow. | Remains role-local until the shared integration workflow. |

The two interfaces must produce equivalent product state for their declared
scope. An implementation difference must not change the selected runtime
account, protected paths, staged-artifact checks, systemd unit behavior,
credential-custody boundary, validation result, or evidence redaction rules.

## Shared Execution Rules

- The operator account is the control-plane identity. Direct root login is not
  a supported workflow identity; privileged OS work uses delegated privilege.
- Reviewed inputs must be verified before mutation. OS dependency provisioning
  may precede application artifact preparation and staging, while staged
  application artifacts must be verified before runtime identity, product-home,
  application, or service mutation.
- Configuration establishes the role runtime and validation observes it.
  `docs/contracts/lifecycle-contract.md` owns the detailed phase and reboot semantics.
- Validation may consume successful earlier checkpoint outcomes and must not
  replay completed setup checks merely to restate their results.
- Gerrit and Jenkins controller use guest systemd in VM simulation and target
  deployment. The outbound Jenkins SSH agent relies on the guest SSH service;
  it does not require a separate Jenkins agent daemon.
- Native operation references contain direct OS and application procedures
  only. They must not include repository helper commands or helper-path
  guidance.
- Setup manuals and helpers must remain aligned with the native procedural
  baseline and produce equivalent product state and validation outcomes.
- Role-local work does not create cross-role keys, credentials, node
  registration, scheduling proof, trigger configuration, or vote proof.
  `docs/operations/setup/integration.md` owns the shared helper workflow and
  `docs/operations/native/integration.md` owns direct integration
  operations.

## Documentation Consumers

Native operation references provide the direct procedure without helper
transcripts. `docs/operations/native/acceptance-checklist.md` records manual
native acceptance outcomes without duplicating those procedures. Setup manuals
describe the reviewed-input helper workflow, including inputs, outputs,
phase-local effects, and handoff. Helper scripts implement that interface, and
simulation documentation realizes the contract for each backend.

Current support status, blockers, waivers, and the next implementation work
belong only in `project-state/execution-status.md`; they are not product-contract facts.
