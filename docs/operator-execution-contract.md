# Operator Execution Contract

## Purpose And Authority

This document owns the durable contract for how an operator executes
Loopforge role and integration work. It defines parity between the native OS
and application procedure and the reviewed-input helper procedure.

It does not own lifecycle phase semantics, role-specific command transcripts,
simulation backend mechanics, evidence schema, or mutable implementation
availability. Those belong respectively to `docs/lifecycle-contract.md`, the
role manuals and native operation references, simulation documentation,
`docs/validation-and-evidence.md`, and `docs/execution-status.md`.

## Operator Interfaces

Target deployment supports two equivalent operator interfaces:

| Aspect | Reviewed-input helper procedure | Native operator procedure |
| --- | --- | --- |
| Execution | Reads reviewed inputs and performs idempotent target operations through delegated privilege. | Operator performs documented OS and application operations through delegated privilege. |
| Service lifecycle | Installs or updates the documented guest systemd units and uses standard systemd control. | Creates or updates the documented guest systemd units and uses standard systemd control. |
| Validation | Performs bounded observational checks and collects redacted evidence. | Operator performs equivalent bounded observational checks and retains target-owned evidence. |
| Scope boundary | Remains role-local until the shared integration workflow. | Remains role-local until the shared integration workflow. |

The two interfaces must produce equivalent product state for their declared
scope. An implementation difference must not change the selected runtime
account, protected paths, staged-artifact checks, systemd unit behavior,
credential-custody boundary, validation result, or evidence redaction rules.

## Shared Execution Rules

- The operator account is the control-plane identity. Direct root login is not
  a supported workflow identity; privileged OS work uses delegated privilege.
- Reviewed inputs and staged artifacts must be verified before role mutation.
- Configuration establishes the role runtime and validation observes it.
  `docs/lifecycle-contract.md` owns the detailed phase and reboot semantics.
- Gerrit and Jenkins controller use guest systemd in VM simulation and target
  deployment. The outbound Jenkins SSH agent relies on the guest SSH service;
  it does not require a separate Jenkins agent daemon.
- Native operation references contain direct OS and application procedures
  only. They must not include repository helper commands or helper-path
  guidance.
- Role-local work does not create cross-role keys, credentials, node
  registration, scheduling proof, trigger configuration, or vote proof.
  `docs/integration-setup-manual.md` owns the shared helper workflow and
  `docs/integration-native-operations-reference.md` owns direct integration
  operations.

## Documentation Consumers

Role manuals describe inputs, outputs, phase-local effects, and handoff.
Native operation references provide the direct procedure without helper
transcripts. Helper scripts implement the reviewed-input interface, and
simulation documentation realizes the contract for each backend.

Current support status, blockers, waivers, and the next implementation work
belong only in `docs/execution-status.md`; they are not product-contract facts.
