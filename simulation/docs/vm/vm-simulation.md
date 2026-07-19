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
`simulation/docs/shared/harness-design.md` and
`simulation/docs/shared/lifecycle-state-model.md`. Cross-layer result acceptance and
workflow checkpoint publication is documented in
`simulation/docs/shared/checkpoint-acceptance-protocol.md`. VM module structure and
implementation contracts are documented in
`simulation/docs/vm/implementation-design.md`. Milestone verification gates
are documented in `simulation/docs/vm/milestone-verification.md`. Shared
generated path custody is documented in
`simulation/docs/shared/generated-state-layout.md`.

VM simulation should be implemented above shared support helpers from
`simulation/lib/` when those helpers exist. Shared helpers cover common
mechanics only; VM lifecycle and transport stay in the VM harness. VM-specific
libvirt/KVM domains, resource groups, snapshots, guest reboot, guest SSH
readiness, guest-owned NFS-backed shared storage, and `create`/`restore-baseline`/
`clean`/`destroy` behavior must not copy Docker backend assumptions such as
Compose project names, Docker service names, Docker bind-mount checks,
loopback port ownership, or Docker transfer waivers.

The VM layer uses the shared topology, account model, version baseline, source
boundaries, and command contract from
`simulation/docs/shared/simulation-model.md`. Generated output conventions come
from `simulation/docs/shared/generated-state-layout.md`. VM hostnames, browser
URLs, SSH host strings, and LDAP endpoint identities follow
`docs/contracts/endpoint-identity.md`.

VM simulation may use simulation-owned fake LDAP bind passwords for its own
LDAP VM, matching Docker simulation. Those values must be labeled as test
credentials and must not be replaced with real organization LDAP secrets.
The default VM LDAP endpoint is the FQDN `ldap.example.test`, derived from
`HARNESS_LDAP_DOMAIN`. Libvirt network DNS remains the source of truth for VM
names and publishes FQDN aliases only; cloud-init configures guests to query
the libvirt gateway DNS with the simulation search domain.

The LDAP VM must run a real LDAP service. VM provisioning seeds the
simulation-owned directory with the entries defined in `simulation/docs/shared/simulation-model.md`
before the clean baseline snapshot is captured. The harness must prove LDAP
service readiness, seeded entry presence, and LDAP bind/search behavior with
simulation-owned test credentials only.
Proof requires the exact expected entry DNs.
A successful LDAP operation with no matching entries is a failure.
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

VM simulation is expected to be near target deployment for product checkpoint
execution. VM-specific mechanisms are allowed for VM
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

After the clean baseline snapshot, product checkpoint work must use target-like
interfaces and paths: target OS SSH as `ci-operator`, SSH file transfer, role
helpers, `scripts/integration-setup.sh`, product APIs, runtime accounts,
target-side checksum verification, and `/var/lib/loopforge/staging/<role>`.

VM simulation must not use libvirt console access, direct guest disk or image
edits, post-baseline cloud-init, host-side injection into guest helper or
product paths, generated target sideband staging, or modeled success without
runtime evidence to complete product checkpoint instances.

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

`simulation/docs/vm/milestone-verification.md` applies the shared lifecycle and evidence
contracts to VM milestones. Its VM-specific gates cover real libvirt resources,
guest SSH, dependency-prepared images, LDAP runtime proof, target-side artifact
transfer, snapshots, and guest service recovery after reboot. It does not define
shared workflow checkpoint success or progression.

## Command Reference

Shared command meanings and state outcomes are authoritative in
`simulation/docs/shared/simulation-model.md` and `simulation/docs/shared/lifecycle-state-model.md`. VM
accepts that command surface through `simulation/vm/simulate.sh`; this section
lists only VM syntax and realization deltas.

VM adds only `reboot --role ROLE|--all` to the shared command grammar.

| Command scope | VM realization |
| --- | --- |
| `preflight` | Checks `flock`, libvirt/KVM access, source image inputs, static harness files, and VM wiring |
| `create`, `start`, `stop`, `status` | Operate on libvirt domains, networks, managed volumes, snapshots, DHCP, SSH readiness, and systemd-backed guests |
| `ssh` | Opens guest OS SSH as the simulation operator account |
| `prepare-artifacts` | Runs role helpers in the bundle-factory VM and exports review archives |
| `stage-artifacts` | Transfers archives over target OS SSH and verifies guest-local manifests and checksums |
| Role and integration phases | Invoke the shared owners over target OS SSH and publish results through the shared checkpoint protocol |
| `reboot` | Reboots selected running guests through the guest OS and waits for machine readiness without performing later validation |
| `audit-state` | Adds an explicit libvirt resource, snapshot, volume, inventory, DHCP, and SSH identity sweep |
| `restore-baseline` | Reverts selected stopped guest disks to their ownership-validated baseline snapshots |
| `clean` | Applies the shared mutable-run cleanup without changing guest disks or reusable libvirt resources |
| `destroy` | Removes only ownership-validated selected domains, networks, volumes, snapshots, seed media, set-local base image, and metadata |

VM commands that mutate host, libvirt, VM, guest OS, Jenkins, or Gerrit state
require explicit operator approval and must describe expected side effects
before mutation. Read-only commands such as `preflight`, `status`, and
`audit-state` must not repair or mutate selected VM resources.

Failure summaries that include `log=` or `evidence=` print full generated
paths so operators can inspect the referenced files directly. VM evidence
records also store full generated bounded-log paths rather than basenames.
Success summaries stay compact and omit log and evidence paths unless a
command's public contract says otherwise.

## VM Resource Namespace

Set/run identity and active-run ownership are shared state-model contracts.
VM-mutating commands include those selected identities in their records without
defining a VM-local identity lifecycle.

The VM harness derives the libvirt resource prefix exactly as
`loopforge-vm-<set-id>`. That injective prefix is backend resource metadata,
remains stable across runs of the set, and must not include `HARNESS_RUN_ID` or
act as another operator identity. Length-limited bridge names use the shared
versioned hash derivation and still require full ownership verification.

## Input Model

If `--env FILE` is omitted, the harness uses the committed
`simulation/vm/examples/vm.env.example` file
defined by the VM harness.

Source/effective input custody and publication are shared contracts in
`simulation/docs/shared/simulation-model.md` and the lifecycle state model. The VM harness adds only
live transport discovery and the private invocation adapter below.

DHCP addresses are live target access and are not written to the stable
effective files. Each `start` refreshes them. Integration phases verify the
owned running domains and SSH identity, copy only the effective
`integration.env` to a private temporary file, overlay the three current target
SSH host fields, invoke the shared helper, and delete the temporary file. Role
env files and stable integration values are never rewritten after publication.

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
fulfillment before the clean baseline boundary; later product checkpoints
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
is defined in `simulation/docs/shared/simulation-model.md`. VM provisioning realizes the default
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

## Host Browser DNS

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

## Generated-State Realization

`simulation/docs/shared/generated-state-layout.md` owns the common set, lock,
and run roots plus their custody and cleanup classes. This section describes
only VM-specific realization deltas.

The baked base image is stored inside the selected simulation set and is
removed by `destroy` with the rest of that set. The target OS SSH identity is
also simulation-set state because its public key is seeded into reusable guest
disks during cloud-init. SSH `known_hosts` trust state remains run-scoped and
is recreated for each selected run.
Seed media installs a root-owned, account-scoped OpenSSH policy that requires
public-key authentication for the VM operator without changing site listener
settings. Cloud-init validates and reloads that policy without restarting the
socket-activated listener. `create` and `start` require successful cloud-init
completion; a missing command or failed cloud-init module blocks readiness.

| VM output kind | VM-specific generated pattern |
| --- | --- |
| Libvirt XML, seed metadata, and baseline snapshot records | `generated/simulation/vm/sets/<set-id>/libvirt/` |
| Target OS SSH identity | `generated/simulation/vm/sets/<set-id>/target-ssh/` |
| Target OS SSH known hosts | `generated/simulation/vm/<run-id>/host/target-ssh/` |
| Exported artifact review copies | `generated/simulation/vm/<run-id>/host/artifacts/exported/<bundle>.tar.gz` |

Artifact staging to service VMs uses target OS SSH into the guest-local
canonical path `/var/lib/loopforge/staging/<role>/`. The generated run tree may
retain host-owned exported artifact review copies, but it must not model VM
target transfer through `target/artifacts/staging/`.

`<set-id>` and `<run-id>` are the identities selected by the shared lifecycle
state model; this section owns only their VM path realization.

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

Shared stop, restore, clean, and destroy rights are defined in the lifecycle
state model. VM realizes them with domain shutdown, snapshot rollback, shared
mutable-run cleanup, and ownership-validated libvirt resource deletion.

`restore-baseline` validates the selected run marker, selected simulation-set
marker, and baseline snapshot records before rollback. It must fail clearly
rather than roll back an unowned, running, or mismatched simulation set.
`destroy` validates simulation-set ownership before deleting any present
domain, network, managed volume, snapshot, seed medium, or set-local base image.

## State Consistency And Recovery

VM applies the shared state model by checking that generated set metadata and
libvirt resources agree:

- The simulation-set marker exists under
  `generated/simulation/vm/sets/<set-id>/`.
- Expected libvirt domains, networks, storage volumes, and baseline snapshots
  exist and carry the selected ownership identity.
- VM SSH host fingerprints match the rendered inventory or are recorded as a
  deliberate first-use capture before mutation.

Legacy or malformed ownership schemas are conflicting state. Normal commands
do not add old-field readers, name-derived recovery, or compatibility cleanup
paths; operators must use an explicit migration or separately approved
host-level cleanup procedure.

## Integration Boundary

VM invokes the shared integration owner over target OS SSH through its private
transport adapter. Integration product checkpoint semantics, workflow
predecessors, evidence acceptance, and failure behavior remain shared.
