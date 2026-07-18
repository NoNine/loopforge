## Step 13: Implement VM Simulation Harness

Implement VM simulation under `simulation/vm/` on top of the shared support
library from Step 12. Do not add a separate numbered scaffold step.

Apply `docs/README.md` before implementation. Task-local companion
docs are:

- `simulation/docs/shared/simulation-model.md` for shared simulation behavior.
- `simulation/docs/vm/vm-simulation.md` for the public VM command contract.
- `simulation/docs/shared/harness-design.md` and
  `simulation/docs/shared/lifecycle-state-model.md` for shared architecture and state
  guards.
- `simulation/docs/vm/implementation-design.md` for VM module boundaries and
  milestone sequence.
- `simulation/docs/vm/decisions/libvirt-module-refactor.md` for the accepted libvirt, VM-set,
  snapshot, seed-media, and baseline-verifier refactor; read it before changing
  those implementation boundaries.
- `simulation/docs/vm/command-sequences.md` for command flow.
- `simulation/docs/vm/milestone-verification.md` for milestone pass/fail gates.

## Roadmap Scope

- Implement the public VM CLI as `simulation/vm/simulate.sh`; command behavior
  is owned by `simulation/docs/vm/vm-simulation.md`.
- Implement the milestone sequence from
  `simulation/docs/vm/implementation-design.md`, M1 through
  M8, without treating those milestones as separate product roadmap steps.
- Keep VM-local implementation under `simulation/vm/` and backend-neutral
  support under `simulation/lib/`; do not depend on Docker harness internals.
- Preserve the VM-specific lifecycle boundaries, target-like post-baseline
  paths, LDAP requirements, evidence requirements, and remote KVM constraints
  defined by the authority and companion docs.
- Defer composite `run` until M8, after individual lifecycle commands are
  credible.

## Environment Constraint

Local-only milestones must not mutate VM, libvirt, host, guest, Gerrit,
Jenkins, or Jenkins agent resources. Real libvirt/KVM lifecycle verification
must run from an approved SSH-accessible remote KVM control node; VM SSH,
product HTTP/SSH, libvirt, NFS, and guest verification commands must execute
there or be reviewed through bounded logs and evidence copied back here.
Remote KVM host setup is external operator infrastructure, not part of
LoopForge. Remote VM, libvirt, or guest mutation requires explicit approval
for the specific target and action.

## Milestone State

Use `simulation/docs/vm/implementation-design.md` for the durable M1-M8
milestone sequence. Use
`project-state/execution-status.md` for the current milestone, completed milestone
state, verification logs, blockers, guardrails, and next authorized work.

## Verification

Verification is milestone-scoped. For each milestone, run syntax checks,
focused tests added for that milestone, docs contract checks, and the VM
commands that are in scope for that milestone. A milestone is not accepted
from marker presence or zero exit alone; the pass/fail gate in
`simulation/docs/vm/milestone-verification.md` must be satisfied, and bounded logs with
contradictory failure evidence invalidate matching readiness markers.

M1 verification:

```bash
tests/vm-docs-contract-test.sh
tests/vm-harness-layout-test.sh
tests/vm-harness-status-output-test.sh
bash -n simulation/vm/simulate.sh simulation/vm/lib/*.sh simulation/lib/*.sh
simulation/vm/simulate.sh --help
simulation/vm/simulate.sh preflight --env simulation/vm/examples/vm.env.example
simulation/vm/simulate.sh --env simulation/vm/examples/vm.env.example init-run
simulation/vm/simulate.sh --env simulation/vm/examples/vm.env.example status
simulation/vm/simulate.sh --env simulation/vm/examples/vm.env.example audit-state
git diff --check
```

M2-M8 verification remains milestone-scoped. M3 and later lifecycle checks
require an approved KVM-capable VM environment. Remote VM, libvirt, or guest
mutation requires explicit approval for the specific target and action.

| Milestone | Additional verification beyond earlier milestones |
| --- | --- |
| M2 | Add `tests/vm-harness-terminal-summary-test.sh`; re-run M1 checks with libvirt preflight and VM-set ownership validation enabled. |
| M3 | Run `create`, `start`, `status`, `ssh --role ROLE`, and `stop`; verify target OS SSH access without role mutation. |
| M4 | Add `tests/vm-harness-ldap-seed-test.sh`; verify role OS dependency baseline readiness, LDAP readiness, seed, bind/search, and consumer reachability before baseline snapshot capture. |
| M5 | Run `restore-baseline`, `clean`, `destroy`, and `audit-state`; verify rollback, generated-state cleanup, and destruction ownership checks after baseline prerequisites are proven. |
| M6 | Add `tests/vm-harness-artifact-lifecycle-test.sh`; run `prepare-artifacts` and `stage-artifacts`; verify target-side manifests and checksums. |
| M7 | Run `configure-role`, `validate-role`, `reboot --all`, and validation after reboot. |
| M8 | Run `configure-integration`, `validate-integration`, `prove-integration`, and `run`; verify proof marker rules. |

## Acceptance

Full Step 13 acceptance requires the complete VM lifecycle in an approved VM
environment. The accepted lifecycle must cover VM creation/startup, artifact
preparation and staging, role configuration and validation, integration
configuration, validation and proof, reboot proof, shutdown, and clean
rollback. Acceptance must not claim `target-deployment` readiness from VM
simulation evidence.

Step 13a owns reusable simulation lifecycle alignment, Step 13b owns the
fresh-state role correction, and Step 13c owns the shared-integration
correction discovered during M8. Earlier runs remain diagnostic evidence for
the prior implementation and do not satisfy the refined lifecycle contracts.
Step 13 integration acceptance cannot close until Steps 13a-13c complete and a
new generated VM run passes the Step 13c M6 full composite gate.
