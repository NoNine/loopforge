# VM Simulation

VM simulation is the second simulation layer for the v1 Gerrit/Jenkins setup
package. It repeats the Docker-verified flow in a libvirt/KVM-backed,
systemd-oriented VM environment. VM simulation is still `vm-simulation`
evidence, not `target-deployment` evidence.

The single VM entrypoint is:

```bash
simulation/vm/simulate.sh <command>
simulation/vm/simulate.sh [--env FILE] <command>
```

`simulate.sh` owns VM provisioning, lifecycle commands, role-local gates, and
cross-role integration orchestration. Do not add standalone VM phase scripts or
a second VM simulation CLI.

Shared architecture and exact state behavior are documented in
`simulation/docs/harness-design.md` and
`simulation/docs/lifecycle-state-model.md`. VM module structure and
implementation contracts are documented in
`simulation/vm/docs/implementation-design.md`. Milestone verification gates
are documented in `simulation/vm/docs/verification.md`.

VM simulation should be implemented above shared support helpers from
`simulation/lib/` when those helpers exist. Shared helpers cover common
mechanics only; VM lifecycle and transport stay in the VM harness. VM-specific
libvirt/KVM domains, resource groups, snapshots, guest reboot, guest SSH
readiness, guest-owned NFS-backed shared storage, and `create`/`restore-baseline`/
`clean`/`destroy` behavior must not copy Docker backend assumptions such as
Compose project names, Docker service names, Docker bind-mount checks,
loopback port ownership, or Docker transfer waivers.

The VM layer uses the shared topology, account model, version baseline, source
boundaries, output conventions, and checkpoint contract from
`simulation/README.md`. VM hostnames, browser URLs, SSH host strings, and LDAP
endpoint identities follow `docs/contracts/endpoint-identity.md`.

VM simulation may use simulation-owned fake LDAP bind passwords for its own
LDAP VM, matching Docker simulation. Those values must be labeled as test
credentials and must not be replaced with real organization LDAP secrets.
The default VM LDAP endpoint is the FQDN `ldap.example.test`, derived from
`HARNESS_LDAP_DOMAIN`. Libvirt network DNS remains the source of truth for VM
names and publishes FQDN aliases only; cloud-init configures guests to query
the libvirt gateway DNS with the simulation search domain.

The LDAP VM must run a real LDAP service. VM provisioning seeds the
simulation-owned directory with the entries defined in `simulation/README.md`
before the clean baseline snapshot is captured. The harness must prove LDAP
service readiness, seeded entry presence, and LDAP bind/search behavior with
simulation-owned test credentials only.
The committed VM seed source is `simulation/vm/ldap/50-harness-seed.ldif`;
the harness renders it into simulation-set seed media before applying it inside the
LDAP VM.

Gerrit and Jenkins controller role envs use the VM LDAP endpoint identity from
the rendered VM inventory. Before role configuration, the harness verifies the
LDAP endpoint is reachable from the Gerrit and Jenkins controller VMs. Missing
or drifted seeded LDAP assumptions fail or block VM readiness; the VM harness
must not model LDAP success without runtime evidence.

The bundle factory VM runs role helper `prepare-artifacts` commands. It is an
environment, not a public API, and there is no standalone
`bundle-factory-helper.sh`.

## Near-Target Lifecycle Boundary

VM simulation is expected to be near target deployment for lifecycle
checkpoint execution. VM-specific mechanisms are allowed for VM
infrastructure work: libvirt/KVM provisioning, seed media or cloud-init base
OS bootstrap before the clean baseline snapshot, automatic baked base-image
preparation for simulation-owned OS dependencies, baseline snapshot
capture/rollback, VM start/stop/destruction, simulation-set ownership inspection, and
guest-owned NFS setup.

VM provisioning must satisfy the role target OS dependency baselines before
the clean baseline snapshot is captured. The `create` command bakes one
simulation-owned, dependency-prepared base image inside the selected simulation set,
then creates the five role disks from that base image. Role helpers validate
those package and command expectations later; they do not install Ubuntu/OS dependencies.

After the clean baseline snapshot, checkpoint work must use target-like
interfaces and paths: target OS SSH as `ci-operator`, SSH file transfer, role
helpers, `scripts/integration-setup.sh`, product APIs, runtime accounts,
target-side checksum verification, and `/var/lib/loopforge/staging/<role>`.

VM simulation must not use libvirt console access, direct guest disk or image
edits, post-baseline cloud-init, host-side injection into guest helper or
product paths, generated target sideband staging, or modeled success without
runtime evidence to complete lifecycle checkpoints.

VM guest service lifecycle follows the target-deployment contract. Gerrit and
Jenkins controller use guest systemd units; the outbound Jenkins agent relies
on the guest `ssh.service` or `sshd.service`. `configure-role` establishes
these runtimes, while `validate-role` only observes enabled/active units,
runtime ownership, endpoints, and bounded logs. The VM harness manages VM
lifecycle, not application service lifecycle.

## Shared Base-Image Service Waiver

The shared baked image installs all roles' OS packages, which leaves `slapd`,
`nfs-server`, and `rpcbind` running on every VM. This is accepted for v1 VM
simulation only; LDAP remains owned by the LDAP VM and the NFS export by the
Jenkins agent.

The waiver requires:

- the selected network is libvirt NAT with local-only DNS and no inbound port
  forwarding;
- credentials and entries are simulation-only, non-LDAP VMs contain no seeded
  identities, and consumers use the configured LDAP FQDN;
- non-agent VMs publish no NFS exports, while the Jenkins agent exports only
  the reviewed shared-storage path;
- all guests are healthy and required role and integration proofs pass.

This waiver does not apply to target deployment, external VM exposure, real
credentials or data, or extra NFS exports. `audit-state` alone does not prove
the conditions. Retire the waiver by quiescing package-enabled services in the
baked image and enabling only role-owned services on each VM.

## Milestone Verification Gates

VM milestone completion requires fail-closed runtime proof. Terminal summaries,
marker files, and evidence records summarize checks; they are not proof by
themselves when bounded logs contain contradictory failures. A command must not
emit a readiness marker such as `baseline-prereqs=ready`, role validation
success, integration validation success, or proof success until the runtime
assertions for that milestone have passed.

The detailed gate contract is `simulation/vm/docs/verification.md`. Public command
behavior follows these rules:

- `create` fails closed when VM provisioning, target OS SSH readiness, role OS
  dependency image bake or reuse, command availability, LDAP service
  readiness, LDAP seed proof, or LDAP consumer reachability cannot be proven.
- LDAP seed and consumer proof requires the exact expected entry DNs; a
  successful LDAP operation with no matching entries is a failure.
- `clean` and `destroy` fail closed unless selected simulation-set ownership and
  rollback or deletion boundaries are proven first.
- `prepare-artifacts` and `stage-artifacts` fail closed unless manifests,
  checksums, source-boundary labels, transfer, and target-side staging are
  proven.
- `validate-role`, `validate-integration`, and `prove-integration` fail closed
  unless the already-running real service, product API, scheduling, trigger,
  build, or vote behavior claimed by the command is proven.

## Command Reference

This section owns VM command behavior. The command-to-checkpoint mapping is
summarized in `docs/contracts/lifecycle-contract.md`.

Composite commands:

| Command | Purpose |
| --- | --- |
| `run [--env FILE]` | Initializes fresh state or resumes the exact active immutable run at its next required phase, leaving the set running. An exact completed run returns `already-complete`; interrupted, conflicting, restored, run-ID-mismatched, or input-changed state blocks. It does not run `stop`, `restore-baseline`, `clean`, `destroy`, or `audit-state`. |
| `ssh [--env FILE] --role ROLE` | Opens an interactive host-to-target OS SSH session using the rendered Standard Interfaces target inventory. This is for target OS access as the operator account, not Gerrit service SSH. |

Phase and lifecycle commands:

| Command | Purpose |
| --- | --- |
| `preflight [--env FILE]` | Validates required local tooling, including `flock`, libvirt/KVM access, static harness files, baseline labels, source-boundary labels, and script wiring. Terminal output is a short `preflight: ok ...` summary; details stay in generated evidence. |
| `init-run [--env FILE]` | Resolves `HARNESS_SET_ID`, generates a collision-resistant immutable `HARNESS_RUN_ID` when omitted or accepts an unused explicit value, copies selected inputs into private runtime inputs, writes rendered/runtime env files, records VM inventory expectations, and creates the simulation set's active-run pointer. It rejects a set with an active run. |
| `create [--env FILE]` | Defines and baselines an absent claimed set, leaving it stopped. For an exact stopped existing set it verifies set metadata and returns non-mutating `state=existing`; running, unclaimed, restored, partial, drifted, unowned, or mismatched state blocks. |
| `start [--env FILE]` | Starts the selected simulation set and waits for control-plane readiness. From exact-bound state, guest systemd starts configured services without setup mutation. An exact running set returns `state=already-running`; other state blocks. |
| `status [--env FILE]` | Reports coherent absent, unclaimed, stopped, or running VM state, including set/run identity, durable classification, reset gate, and access data when available. Contradictory state reports `conflicting` and exits nonzero. |
| `prepare-artifacts [--env FILE] [--role ROLE]` | Runs one role, or all VM roles when `--role` is omitted, inside the bundle factory VM and exports bundle archives plus checksums. Success prints compact `prepare-artifacts[role]: ok` summaries. |
| `stage-artifacts [--env FILE] [--role ROLE]` | Transfers prepared artifact archives from the bundle factory VM to the target VM, verifies archive manifests and checksums on the target side, and stages them under the helper-visible staging path before mutation. Success prints compact `stage-artifacts[role]: ok` summaries. |
| `configure-role [--env FILE] [--role ROLE]` | Runs one initial role-local configuration phase, or all VM roles when `--role` is omitted, against target VMs, installs fresh guest service state, establishes the role runtime, and records evidence. |
| `validate-role [--env FILE] [--role ROLE]` | Observes one role-local runtime, or all VM roles when `--role` is omitted, against target VMs and records evidence. It must not start, restart, enable, or repair a service. Success prints `validate-role[role]: ok`; failures include `log=` and `evidence=`. |
| `configure-integration [--env FILE]` | Configures shared integration state for Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, shared storage, and the Gerrit Trigger server through `scripts/integration-setup.sh`. Success prints a short `configure-integration: ok` summary. |
| `validate-integration [--env FILE]` | Runs passive cross-role readiness validation and writes a marker for later verification. Success prints a short `validate-integration: ok` summary. |
| `prove-integration [--env FILE]` | Requires a matching successful validate marker for the same run, then runs the active cross-role proof. It does not run `validate-integration` implicitly. Success prints a short `prove-integration: ok` summary. |
| `reboot [--env FILE] [--role ROLE\|--all]` | Reboots selected running VM targets through the guest OS as the operator account with delegated privilege, waits for SSH return and system readiness, then proves required guest services recovered before any later validation. It does not rerun configuration or validation phases implicitly. |
| `audit-state [--env FILE]` | Performs an explicit read-only sweep of selected simulation-set resources, snapshots, generated state, inventory, and run markers. It does not rerun other phases. |
| `stop [--env FILE]` | Gracefully shuts down selected simulation-set domains while retaining VM disks, snapshots, generated state, logs, artifacts, and evidence. An ownership-valid stopped set returns `state=already-stopped` with its durable classification and reset gate. |
| `restore-baseline [--env FILE]` | Requires the selected simulation set to be stopped, validates ownership and baseline snapshot records, and reverts guest disks to the clean baseline. It does not clean generated run state or delete VMs. |
| `clean [--env FILE]` | Requires the set to be stopped and successfully restored, deletes mutable workflow/run state, and removes the active-run pointer last. It preserves the immutable run marker, checkpoint records, retained review output, and VM baseline resources. |
| `destroy [--env FILE]` | Permanently removes an ownership-validated selected set. A fully absent unclaimed set returns `state=already-absent`; missing or mismatched ownership metadata blocks rather than authorizing name-derived deletion. |

`ROLE` is one of `gerrit`, `jenkins-controller`, or `jenkins-agent`. `--all`
for `reboot` includes those service VMs and dependency VMs needed for the
selected run.

VM commands that mutate host, libvirt, VM, guest OS, Jenkins, or Gerrit state
require explicit operator approval and must describe expected side effects
before mutation. Read-only commands such as `preflight`, `status`, and
`audit-state` must not repair or mutate selected VM resources.

Failure summaries that include `log=` or `evidence=` print full generated
paths so operators can inspect the referenced files directly. VM evidence
records also store full generated bounded-log paths rather than basenames.
Success summaries stay compact and omit log and evidence paths unless a
command's public contract says otherwise.

## Simulation Set And Run Identity

VM simulation has two identities:

| Identity | Purpose |
| --- | --- |
| `HARNESS_SET_ID` | Names the reusable simulation set. It uses the shared 1-24 character lowercase letter/digit/internal-hyphen grammar and defaults to `default`. |
| `HARNESS_RUN_ID` | Immutable identity for exactly one setup and validation attempt. `init-run` generates it when omitted; an explicit value must be unused. |

The default experience behaves like a single active simulation set. Most local
runs can omit `HARNESS_SET_ID` and use the implicit `default` set. Advanced
runs may select separate simulation sets for parallel experiments or CI
isolation.

Each simulation set stores one non-secret `active-run.env` pointer. Every
VM-mutating command prints and records the selected set. Every active artifact,
log, marker, and evidence record binds `set_id` and `run_id`. `stop` followed by
`start` preserves both identities.

The VM harness derives the libvirt resource prefix exactly as
`loopforge-vm-<set-id>`. That injective prefix is backend resource metadata,
remains stable across runs of the set, and must not include `HARNESS_RUN_ID` or
act as another operator identity. Length-limited bridge names use the shared
versioned hash derivation and still require full ownership verification.

## Input Model

If `--env FILE` is omitted, the harness uses the committed
`simulation/vm/examples/vm.env.example` file
defined by the VM harness. Copy committed examples outside the examples tree
before using real operator values.

The harness env file must identify role and integration env inputs using the
same role boundaries as Docker simulation. During `init-run`, the selected
harness, role, and integration env files are copied to the run-scoped
`host/runtime-inputs/` directory with mode `0600`. Later lifecycle and cleanup
commands load the private runtime config and verify run and simulation-set
markers before operating. `init-run` rejects a set with an active-run pointer or an
explicit run ID whose canonical root already exists. After `stop`, successful
`restore-baseline`, and `clean`, it generates a new run ID when omitted.

The rendered harness record is written for inspection. Private runtime env
files retain lifecycle values and point at the runtime input copies.
Non-secret run markers and manifest contracts are public/read-only metadata,
not secret material.

## Libvirt/KVM Lifecycle

VM simulation maps Loopforge commands onto libvirt/KVM state deliberately:

| Loopforge command | Libvirt/KVM lifecycle meaning |
| --- | --- |
| `create` | Define the reusable simulation set's VM resources, create owned networks/storage/seed media, boot only as needed for base initialization, and capture the clean baseline snapshot. |
| `start` | Start defined VM domains and wait for control-plane readiness. |
| `reboot` | Reboot guests from inside the OS to prove machine reboot behavior. |
| `stop` | Shut down running domains set-wide while retaining definitions, disks, and snapshots; hard-stop only domains that remain running after the bounded graceful wait. |
| `restore-baseline` | Revert stopped selected VM domains to the baseline snapshot without cleaning generated run state. |
| `clean` | Clean mutable generated run state without reverting guest disks or deleting VM resources. |
| `destroy` | Undefine selected VM domains and remove owned storage, the set-local base image, snapshots, seed media, and networks. |

Libvirt `destroy` is a hard power-off operation, not VM deletion. VM deletion
belongs only to the Loopforge `destroy` command, which uses libvirt undefine
and storage/network removal after validating selected simulation-set ownership.

`restore-baseline` is destructive to guest disk changes made after the
baseline snapshot, but it must not remove the reusable simulation set or generated run
state. The baseline snapshot is captured after OS, cloud-init, target OS
control-plane readiness, SSH host-key capture, VM harness prerequisites, role
OS dependency fulfillment, LDAP service readiness, and LDAP seed verification.
It is captured before Loopforge artifacts are staged, product services are
configured, integration keys are created, or verification changes are made.

M3 provisioning uses Cloud Image Clone. The VM harness consumes a local Ubuntu
Noble cloud image such as `noble-server-cloudimg-amd64.img`, creates
or reuses a simulation-owned baked base image keyed by the selected source
image checksum, Ubuntu baseline, apt mirror, source-boundary label, VM disk
size, and VM package matrix, creates per-machine qcow2 disks for the selected
simulation set, renders cloud-init seed media, imports the domains into libvirt, and
proves target OS SSH as the simulation operator account. The cloud image and
baked base image are VM host infrastructure inputs, not Loopforge application
artifacts. Cloud-init is limited to base OS bootstrap and role OS dependency
fulfillment before the clean baseline boundary; later lifecycle checkpoints
must use target OS SSH and helper-visible paths.

The operator owns pool and volume descriptors, markers, locks, logs, and
evidence. Baked and per-machine qcow2 files become libvirt-managed volumes;
the harness does not depend on their POSIX owner or repair access with
`chmod` or `chown`. It uses libvirt volume metadata for format, capacity, and
backing-store proof and uses mediated volume download for SHA-256 proof.
Domains attach each mutable volume's libvirt-reported path as a file-backed
disk so the host security driver applies its runtime label. Base-image
validity does not depend on the read-only base volume's incidental owner.
Preparation uses a simulation-set-local `flock` lock; the completed volume is recorded
before its ready marker. An existing invalid entry fails closed and is not
replaced because reusable VM disks may depend on it.

Each reusable VM disk records and verifies its storage pool, volume, backing
path, fingerprint, SHA-256, and disk size through libvirt APIs. `create`
rejects legacy unmanaged sets or mismatched volume metadata without changing
the selected VM disks. Select a fresh `HARNESS_SET_ID`, let `init-run` generate
a fresh `HARNESS_RUN_ID`, and run `create`. The rejected state requires an
explicit migration or separately approved host-level cleanup; normal VM
commands do not add legacy ownership readers or delete generated backing
directly.

## Simulation Accounts

The shared simulation account contract, including seeded LDAP login accounts,
is defined in `simulation/README.md`. VM provisioning realizes the default
simulation operator. Role `install` creates or verifies the reviewed product
runtime accounts and product homes inside the target VMs; the VM harness does
not create those identities before invoking the helpers.

VM simulation models Jenkins shared storage as a Jenkins-agent-hosted
NFS-backed shared storage resource. It is target-like guest state, not a
Jenkins runtime home and not a sixth product role. The Jenkins agent VM runs
the NFS server and exports `JENKINS_SHARED_STORAGE_PATH`, normally
`/data/jenkins-shared`; the Jenkins controller VM mounts that export at the
same path before `configure-integration`. That integration phase applies the
shared `jenkins-share` group, setgid group-writable permissions, export and
mount validation, and read/write proof.

Privileged VM operations are delegated from the operator account only when
needed for narrow OS work, such as package installation, protected path
creation, service management, ownership changes, guest reboot, or controlled
shutdown. Root is not a Loopforge account, helper execution identity, runtime
identity, or supported direct login identity.

Use `simulate.sh status --env FILE` after `start` to inspect the selected running
VM simulation. The status command prints the run ID, set ID, derived libvirt
resource prefix, browser URLs, SSH endpoints, and seeded VM simulation login
accounts.

When the VM browser URLs use FQDNs such as
`http://gerrit.example.test:8080/`, the libvirt network DNS owns those names
inside the VM network. The KVM host may still need a temporary split-DNS route
so host-side browsers and tools resolve the VM domain through the selected
libvirt gateway. The helper below discovers the selected VM network from the
same env defaults as `simulate.sh`, checks libvirt DNS, and can apply or undo
runtime-only `systemd-resolved` link settings:

```bash
simulation/vm/tools/configure-systemd-resolved.sh --dry-run
simulation/vm/tools/configure-systemd-resolved.sh --env FILE --apply
simulation/vm/tools/configure-systemd-resolved.sh --env FILE --revert
```

If `--env FILE` is omitted, the helper uses
`simulation/vm/examples/vm.env.example`, matching the VM simulation CLI
default. No-option execution defaults to `--dry-run`; `--dry-run` is read-only
and does not require privileged access.
`--apply` and `--revert` require non-interactive sudo, fail fast when it is
unavailable, and mutate only systemd-resolved's temporary per-link runtime
state for the selected bridge. The helper does not edit `/etc/hosts`,
`/etc/resolv.conf`, NetworkManager profiles, dnsmasq configuration, systemd
unit files, or persistent network files.

Use `simulate.sh ssh --role ROLE` after `start` to log into a target OS
environment as the target-local `ci-operator` through SSH from the host. The
command uses the rendered `INTEGRATION_*_TARGET_SSH_*` values and the
simulation-set target SSH key plus run-scoped known-hosts file:

```bash
simulation/vm/simulate.sh ssh --role gerrit
simulation/vm/simulate.sh ssh --role jenkins-controller
simulation/vm/simulate.sh ssh --role jenkins-agent
```

This command intentionally uses the target OS control-plane SSH interface. It
does not use libvirt console access and it is separate from Gerrit's service
SSH on port `29418`.

## Output Locations

VM-generated runtime output is not committed. VM simulation uses generated
repo-local roots for reusable simulation-set state and run-scoped output:

```text
generated/simulation/vm/sets/<set-id>/
generated/simulation/vm/locks/<set-id>.lock
generated/simulation/vm/<run-id>/
```

Simulation-set state persists across runs until `destroy`. Run-scoped output
is tied to `HARNESS_RUN_ID` and may be cleaned or retained independently. The
baked base image is stored inside the selected simulation set and is removed
by `destroy` with the rest of that set. The target OS SSH identity is also
simulation-set state because its public key is seeded into reusable guest disks
during cloud-init. SSH `known_hosts` trust state remains run-scoped and is
recreated for each selected run.
Seed media installs a root-owned, account-scoped OpenSSH policy that requires
public-key authentication for the VM operator without changing site listener
settings. Cloud-init validates and reloads that policy without restarting the
socket-activated listener. `create` and `start` require successful cloud-init
completion; a missing command or failed cloud-init module blocks readiness.

| Output kind | VM generated pattern |
| --- | --- |
| Simulation-set registry and ownership metadata | `generated/simulation/vm/sets/<set-id>/` |
| Stable simulation-set lock | `generated/simulation/vm/locks/<set-id>.lock` |
| Workflow head and immutable checkpoint records | `generated/simulation/vm/<run-id>/host/state/` |
| Libvirt XML, seed metadata, and baseline snapshot records | `generated/simulation/vm/sets/<set-id>/libvirt/` |
| Target OS SSH identity | `generated/simulation/vm/sets/<set-id>/target-ssh/` |
| Host-contributed run inputs | `generated/simulation/vm/<run-id>/host/` |
| Private runtime input copies | `generated/simulation/vm/<run-id>/host/runtime-inputs/` |
| Target OS SSH known hosts | `generated/simulation/vm/<run-id>/host/target-ssh/` |
| Harness evidence | `generated/simulation/vm/<run-id>/host/evidence/harness/` |
| Harness bounded logs | `generated/simulation/vm/<run-id>/host/logs/harness/` |
| Integration evidence and logs | `generated/simulation/vm/<run-id>/host/evidence/integration/`, `host/logs/integration/` |
| Exported artifact review copies | `generated/simulation/vm/<run-id>/host/artifacts/exported/<bundle>.tar.gz` |
| Target role evidence | `generated/simulation/vm/<run-id>/target/evidence/<role>/` |
| Target role bounded logs | `generated/simulation/vm/<run-id>/target/logs/<role>/` |

Artifact staging to service VMs uses target OS SSH into the guest-local
canonical path `/var/lib/loopforge/staging/<role>/`. The generated run tree may
retain host-owned exported artifact review copies, but it must not model VM
target transfer through `target/artifacts/staging/`.

`<set-id>` defaults to `default` when `HARNESS_SET_ID` is omitted.
`<run-id>` uniquely identifies one immutable attempt. The simulation-set-scoped
`active-run.env` pointer contains that run ID and its marker fingerprint.

These paths are generated runtime output unless a file in the tree states
otherwise. Keep them ignored or documented as generated when created by
simulation steps.

## Failed Bake Debugging

`VM_DEBUG_PRESERVE_FAILED_BAKE=1` is an opt-in diagnostic setting. The default
is `0`, which keeps normal failure cleanup unchanged. The setting is persisted
by `init-run` but does not change the baked-image content fingerprint.

When enabled, a failed base-image bake retains its transient libvirt domain,
qcow2 work disk, seed media, domain XML, and private simulation-set debug
marker. The `create` command still fails nonzero and does not emit readiness
markers. Its bounded log reports the retained domain, work directory, marker,
and required cleanup action.

Do not rerun `create` against that simulation set. The harness fails closed
while the debug marker exists so the next attempt cannot replace diagnostic
evidence. Inspect the retained guest and files, then remove the selected state
with its retained environment file:

```bash
simulation/vm/simulate.sh --env FILE destroy
```

`stop`, `clean`, and another `create` do not recover preserved bake state.
The ownership-checked `destroy` command removes the transient domain, bake
work directory, marker, network, storage, and remaining selected
simulation-set state.

## Cleanup And Destruction

Host-wide libvirt recovery is available as a separate operator tool:

```bash
simulation/vm/tools/cleanup-libvirt-resources.sh --dry-run
sudo simulation/vm/tools/cleanup-libvirt-resources.sh --destroy
```

The dry run inventories every `loopforge-vm-*` domain, managed volume, pool,
and network plus every `lf-*` bridge and prints the ordered removal actions
without mutation. No-option execution is also a dry run. Actual cleanup uses
`--destroy`, requires root, deletes all matching libvirt resources through
libvirt APIs before removing residual LoopForge bridges, and fails if any
matching resource remains. If an inactive LoopForge directory pool still
exists in libvirt but its target path has already been removed, the
tool reports the missing target and undefines the empty pool without
recreating the path. It does not remove generated workspaces, logs, evidence,
test images, or source cloud images. This is a host-wide recovery tool, not
the ownership-checked, selected simulation-set behavior of the M5 `destroy`
command.

`stop`, `restore-baseline`, `clean`, and `destroy` are deliberately separate:

- `stop` stops selected VM domains and preserves VM state.
- `restore-baseline` rolls back stopped guest disks in the selected simulation
  set to the clean baseline snapshot. It preserves generated state for review
  and debugging.
- `clean` removes mutable generated state for the selected run only. It
  requires the selected simulation set to be stopped and successfully restored
  to the matching baseline, and preserves exported artifacts, evidence, bounded
  logs, the immutable run marker, checkpoint completion records, and the
  simulation-set target SSH identity. It removes run-scoped SSH known-hosts,
  the mutable workflow head, and the set's active-run pointer last, then permits
  `init-run` to generate a new run ID.
- `destroy` permanently deletes the selected simulation set and its owned
  libvirt resources, including the set-local base image and target
  SSH identity.

`restore-baseline` validates the selected run marker, selected simulation-set
marker, and baseline snapshot records before rollback. It must fail clearly
rather than roll back an unowned, running, or mismatched simulation set.
`clean` validates the selected run marker and set before generated-state cleanup.
`destroy` requires ownership-valid simulation-set metadata before deleting any
present libvirt resource. A fully absent unclaimed set is an idempotent
`already-absent` success. Missing resources contradicted by retained metadata,
or present resources without their ownership metadata, are conflicting state
and block.

## State Consistency And Recovery

The selected simulation set is consistent only when generated set metadata and
libvirt resources agree:

- The simulation-set marker exists under
  `generated/simulation/vm/sets/<set-id>/`.
- Expected libvirt domains, networks, storage volumes, and baseline snapshots
  exist and carry the selected ownership identity.
- The generated run marker exists under `generated/simulation/vm/<run-id>/`
  and matches the simulation set's `active-run.env` pointer.
- The strict run-scoped `workflow-state.env` and its hash-linked checkpoint
  records match the pointer, marker, baseline, and reviewed input fingerprints.
- Rendered runtime config exists and fingerprints match the run marker.
- Runtime input copies exist for the harness, Gerrit, Jenkins controller,
  Jenkins agent, and integration env files.
- VM SSH host fingerprints match the rendered inventory or are recorded as a
  deliberate first-use capture before mutation.

If generated state, simulation-set metadata, snapshots, or libvirt resources
are inconsistent, lifecycle phases fail clearly instead of recreating state or
rerunning earlier phases. Recover with explicit `stop`, `restore-baseline`,
`clean`, or `destroy` commands for the selected simulation set and run.

Legacy or malformed ownership schemas are conflicting state. Normal commands
do not add old-field readers, name-derived recovery, or compatibility cleanup
paths; operators must use an explicit migration or separately approved
host-level cleanup procedure.

Typical flow:

```bash
simulation/vm/simulate.sh --env FILE init-run
simulation/vm/simulate.sh --env FILE create
simulation/vm/simulate.sh --env FILE start
simulation/vm/simulate.sh --env FILE prepare-artifacts
simulation/vm/simulate.sh --env FILE stage-artifacts
simulation/vm/simulate.sh --env FILE configure-role
simulation/vm/simulate.sh --env FILE validate-role
simulation/vm/simulate.sh --env FILE configure-integration
simulation/vm/simulate.sh --env FILE validate-integration
simulation/vm/simulate.sh --env FILE prove-integration
simulation/vm/simulate.sh --env FILE reboot --all
# Prove unit recovery before the following observational checks.
simulation/vm/simulate.sh --env FILE validate-role
simulation/vm/simulate.sh --env FILE validate-integration
simulation/vm/simulate.sh --env FILE stop
simulation/vm/simulate.sh --env FILE restore-baseline
simulation/vm/simulate.sh --env FILE clean
```

Use `destroy` only when the reusable simulation set should be permanently removed.

## Integration Boundary

Role helpers stay role-local. Cross-role SSH, Gerrit Trigger setup,
integration validation, trigger verification, and integration evidence use
`scripts/integration-setup.sh`.

`validate-integration` and `prove-integration` must fail or report blocked
rather than claim VM readiness when real integration proof is unavailable.
Forbidden synthetic success markers in role or integration logs are treated as
failures.

`up` and `down` are unsupported command names. The CLI must reject them and
must not provide compatibility aliases.

Public internet fallback on target hosts is simulation-only and applies only
to Ubuntu/OS dependency installation. It is not a fallback for target-host
application artifact downloads, and v1 is not a strict air-gapped installer.
