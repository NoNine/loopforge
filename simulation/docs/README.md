# Simulation Documentation

## Purpose

This directory is the entrypoint for Loopforge simulation documentation. It
routes readers to the document that owns each shared, Docker, or VM simulation
fact. It is an index, not a behavioral authority.

Use `docs/README.md` to resolve repository-wide documentation authority and
`docs/contracts/lifecycle-contract.md` for product checkpoint semantics.

## Documentation Map

| Scope | Document | Responsibility |
| --- | --- | --- |
| Shared | `shared/simulation-model.md` | Public simulation model, topology, terminology, command semantics, and source boundaries |
| Shared | `shared/generated-state-layout.md` | Host-side generated roots, path custody, sensitivity, and cleanup classes |
| Shared | `shared/harness-design.md` | Backend-neutral harness architecture and dependency boundaries |
| Shared | `shared/lifecycle-state-model.md` | Exact simulation state, guards, transitions, and recovery rights |
| Shared | `shared/run-plan-transition-protocol.md` | Structured checkpoint-result capture, verification, and run-step commitment |
| Shared | `shared/operation-records.md` | Simulation resource-lifecycle operation records |
| Shared | `shared/terminal-output.md` | Cross-backend terminal presentation conventions |
| Docker | `docker/docker-simulation.md` | Docker command syntax and backend realization |
| Docker | `docker/implementation-design.md` | Docker module structure and dependency direction |
| VM | `vm/vm-simulation.md` | VM command syntax and backend realization |
| VM | `vm/implementation-design.md` | VM module structure and provisioning decisions |
| VM | `vm/command-sequences.md` | VM command flow through internal capabilities |
| VM | `vm/milestone-verification.md` | VM milestone pass/fail gates |
| VM | `vm/decisions/` | Narrow VM implementation decisions |

## Reading Order

For shared simulation behavior, read `shared/simulation-model.md`, then the
shared companion that owns the affected contract. Read
`shared/generated-state-layout.md` for generated storage questions. For backend
work, read the shared model and applicable shared companions before the backend
simulation guide and implementation companions.

Implementation plans under `docs/planning/` provide sequencing and historical
context. They do not replace the simulation authorities listed here. Mutable
resume state remains in `project-state/execution-status.md`.
