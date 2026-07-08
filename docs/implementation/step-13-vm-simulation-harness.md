## Step 13: Implement VM Simulation Harness

Implement real VM simulation under `simulation/vm/` on top of the shared
support library from Step 12. Do not add a separate numbered scaffold step.

For VM harness work, apply `docs/docs-management.md` first. The task-local
companion documents are `simulation/README.md` for shared simulation behavior,
`simulation/vm/README.md` for public VM command behavior,
`simulation/vm/design.md` for internal module and milestone structure, and
`simulation/vm/sequences.md` for command flow. Implement this step milestone
by milestone using the sequence in `simulation/vm/design.md`: M1 harness
skeleton and read-only run state through M8 integration proof and composite
`run`. These milestones are internal implementation slices, not separate
product roadmap steps.

The public command contract remains the full VM command surface below, but
commands become complete only when their milestone is reached. Earlier
milestones may implement partial read-only behavior or fail clearly with a
blocked or not-implemented summary.

Expected command surface:

```text
simulation/vm/simulate.sh run
simulation/vm/simulate.sh preflight
simulation/vm/simulate.sh init-run
simulation/vm/simulate.sh create
simulation/vm/simulate.sh up
simulation/vm/simulate.sh status
simulation/vm/simulate.sh ssh
simulation/vm/simulate.sh prepare-artifacts
simulation/vm/simulate.sh stage-artifacts
simulation/vm/simulate.sh configure-role
simulation/vm/simulate.sh validate-role
simulation/vm/simulate.sh configure-integration
simulation/vm/simulate.sh validate-integration
simulation/vm/simulate.sh prove-integration
simulation/vm/simulate.sh reboot
simulation/vm/simulate.sh audit-state
simulation/vm/simulate.sh down
simulation/vm/simulate.sh clean
simulation/vm/simulate.sh destroy
```

Implementation notes:

- Use separate bundle factory, LDAP, Gerrit, Jenkins controller, and Jenkins
  agent VMs.
- The LDAP VM must run a real LDAP service, not only exist as an empty VM.
  Seed the simulation directory with the entries defined in
  `simulation/README.md`. Use simulation-owned test credentials only; never
  consume real organization LDAP secrets in VM simulation.
- Keep `simulation/vm/simulate.sh` as the public VM simulation CLI and thin
  command dispatcher where practical.
- Put VM-local implementation groups under `simulation/vm/lib/*.sh`.
  Candidate groups are libvirt/KVM lifecycle, VM inventory, SSH transport,
  artifact staging, evidence, generated state, and command implementations.
- Follow the folded initial module layout and split triggers documented in
  `simulation/vm/design.md`.
- Start with M1: CLI dispatch, runtime input custody, generated run paths,
  run markers, partial read-only `status`, and partial read-only
  `audit-state`. M1 must not create, modify, or delete libvirt resources.
- Defer composite `run` until M8, after individual lifecycle commands are
  credible.
- VM implementation may source backend-neutral helpers from `simulation/lib/`
  and VM-local helpers from `simulation/vm/lib/`. It must not source or depend
  on Docker harness internals under `simulation/docker/lib/`.
- Implement reusable VM set identity, run identity, ownership metadata, and
  generated output paths as documented in `simulation/vm/README.md`.
- Implement `create`, `up`, `reboot`, `down`, `clean`, and `destroy` with
  libvirt/KVM semantics. `clean` rolls back to the baseline snapshot and does
  not delete VMs; `destroy` is the only command that removes VM resources.
- Install VM guest OS dependencies during `create` as part of pre-baseline
  guest preparation, before role configuration, artifact staging, or
  integration setup.
- Capture the baseline snapshot after OS, cloud-init, SSH readiness, host-key
  capture, VM harness prerequisites, LDAP service readiness, and LDAP seed
  verification, before Loopforge artifact staging or Gerrit/Jenkins service
  configuration.
- Implement VM-set-owned NFS-backed Jenkins shared storage and mount it into
  controller and agent VMs at `JENKINS_SHARED_STORAGE_PATH`.
- Render Gerrit and Jenkins controller role envs to use the VM LDAP endpoint
  identity from VM inventory. Verify LDAP bind/search on the LDAP VM and LDAP
  endpoint reachability from Gerrit and Jenkins controller VMs before role
  configuration. Fail or block VM readiness if seeded LDAP assumptions are
  missing or drifted.
- Run `prepare-artifacts` on the bundle factory VM, stage prepared archives to
  service VMs, and verify target-side manifests and checksums before mutation.
- Run role helpers only for role-local lifecycle and call
  `scripts/integration-setup.sh` for cross-role integration setup,
  validation, proof, and evidence.
- Use target OS SSH as the operator account for helper execution, staging,
  validation, evidence collection, and interactive `ssh --role`.
- After the clean baseline snapshot, implement checkpoint work through
  target-like interfaces and paths: target OS SSH, SSH file transfer, role
  helpers, `scripts/integration-setup.sh`, product APIs, runtime accounts,
  target-side checksum verification, and `/var/lib/loopforge/staging/<role>`.
- Keep libvirt/KVM lifecycle, VM snapshots, guest SSH readiness, NFS-backed
  storage, reboot behavior, and VM destruction local to the VM harness.
- Limit VM-specific shortcuts to infrastructure lifecycle and baseline
  management. Do not use libvirt console access, direct guest disk or image
  edits, post-baseline cloud-init, host-side injection into guest
  helper/product paths, or generated target sideband staging to complete
  checkpoint work.
- Do not copy Docker assumptions such as Compose project names, Docker service
  names, bind-mount checks, loopback port ownership, Docker `cp` waivers, or
  Docker cleanup recovery.
- The current development host cannot provide KVM and cannot directly reach VMs
  created on a remote KVM-capable machine. Real libvirt/KVM lifecycle
  verification must run from an approved SSH-accessible remote KVM control
  node; VM SSH, product HTTP/SSH, libvirt, NFS, and guest verification commands
  must execute there or be reviewed through bounded logs and evidence copied
  back here. Remote KVM host setup is external operator infrastructure, not
  part of LoopForge.
- VM commands that mutate host, libvirt, guest OS, Gerrit, Jenkins, or Jenkins
  agent state require explicit operator approval and must describe expected
  side effects.
- VM verification must use the Step 10 evidence model, record Version Baseline
  values, and fail or block when the selected VM versions drift from the
  reviewed baseline.
- VM evidence must record LDAP service readiness, seeded account/group
  presence, bind/search proof, LDAP endpoint identity, and redaction status.
  Evidence must label LDAP as simulation/test LDAP and must not include LDAP
  passwords or bind secrets.

Verification:

Verification is milestone-scoped. For each milestone, run syntax checks,
focused tests added for that milestone, docs contract checks, and the VM
commands that are in scope for that milestone.

M1 verification:

```bash
tests/vm-docs-contract-test.sh
tests/vm-harness-layout-test.sh
bash -n simulation/vm/simulate.sh simulation/vm/lib/*.sh simulation/lib/*.sh
simulation/vm/simulate.sh --help
simulation/vm/simulate.sh preflight --env simulation/vm/example.env
simulation/vm/simulate.sh --env simulation/vm/example.env init-run
simulation/vm/simulate.sh --env simulation/vm/example.env status
simulation/vm/simulate.sh --env simulation/vm/example.env audit-state
git diff --check
```

M2-M8 verification remains milestone-scoped. M3 and later lifecycle checks
require an approved KVM-capable VM environment. Remote VM, libvirt, or guest
mutation requires explicit approval for the specific target and action.

| Milestone | Additional verification beyond earlier milestones |
| --- | --- |
| M2 | Re-run M1 syntax, docs, layout, `preflight`, and `audit-state` checks with libvirt preflight and VM-set ownership validation enabled. |
| M3 | Run `create`, `up`, `status`, `ssh --role ROLE`, and `down`; verify target OS SSH as `ci-operator` for each service role without Loopforge role mutation. |
| M4 | Run `clean`, `destroy`, and `audit-state`; verify baseline rollback and destruction require selected VM-set ownership metadata. |
| M5 | Add `tests/vm-harness-ldap-seed-test.sh`; verify LDAP readiness, seeded entries, bind/search proof, and endpoint reachability from Gerrit and Jenkins controller VMs. |
| M6 | Run `prepare-artifacts` and `stage-artifacts`; verify target-side manifests and checksums under `/var/lib/loopforge/staging/<role>`. |
| M7 | Run `configure-role`, `validate-role`, `reboot --all`, and `validate-role` again; verify role evidence and post-reboot service readiness. |
| M8 | Run `configure-integration`, `validate-integration`, `prove-integration`, and `run`; verify proof requires a matching validation marker. |

Full Step 13 acceptance still requires the complete VM lifecycle in an
approved VM environment:

```bash
tests/vm-docs-contract-test.sh
tests/vm-harness-layout-test.sh
tests/vm-harness-ldap-seed-test.sh
bash -n simulation/vm/simulate.sh simulation/vm/lib/*.sh simulation/lib/*.sh
simulation/vm/simulate.sh --help
simulation/vm/simulate.sh preflight --env simulation/vm/example.env
simulation/vm/simulate.sh --env simulation/vm/example.env init-run
simulation/vm/simulate.sh --env simulation/vm/example.env create
simulation/vm/simulate.sh --env simulation/vm/example.env up
simulation/vm/simulate.sh --env simulation/vm/example.env prepare-artifacts
simulation/vm/simulate.sh --env simulation/vm/example.env stage-artifacts
simulation/vm/simulate.sh --env simulation/vm/example.env configure-role
simulation/vm/simulate.sh --env simulation/vm/example.env validate-role
simulation/vm/simulate.sh --env simulation/vm/example.env configure-integration
simulation/vm/simulate.sh --env simulation/vm/example.env validate-integration
simulation/vm/simulate.sh --env simulation/vm/example.env prove-integration
simulation/vm/simulate.sh --env simulation/vm/example.env reboot --all
simulation/vm/simulate.sh --env simulation/vm/example.env down
simulation/vm/simulate.sh --env simulation/vm/example.env clean
git diff --check
```

Acceptance criteria:

- VM simulation provisions or verifies the five-VM topology and records both
  VM set identity and run identity in evidence.
- The LDAP VM runs a real seeded LDAP service, proves bind/search behavior,
  and exposes the reviewed VM LDAP endpoint to Gerrit and Jenkins controller
  role configuration.
- Artifact preparation, staging, role configuration, role validation, shared
  integration setup, cross-role validation, and end-to-end proof run against
  real VMs instead of modeled success.
- Reboot proof exercises guest OS reboot behavior and verifies service
  readiness after return.
- Cleanup rolls back mutable VM state without deleting reusable VMs, and
  destruction removes only simulation-owned VM resources after ownership
  validation.
- Evidence labels the mode as VM simulation and does not imply
  target-deployment acceptance unless a separate target-deployment review says
  so.

