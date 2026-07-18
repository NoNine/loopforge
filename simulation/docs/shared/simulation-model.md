# Simulation Model

This document defines the shared simulation model for the v1 Gerrit/Jenkins
setup package. Layer-specific command syntax and backend realization live in
the Docker and VM simulation guides; this file owns shared command semantics,
topology, source boundaries, output conventions, and simulation realization.
`docs/contracts/lifecycle-contract.md` owns checkpoint semantics for all modes.

Shared internal architecture is defined in
`simulation/docs/shared/harness-design.md`. Exact simulation state dimensions,
command guards, and transitions are defined in
`simulation/docs/shared/lifecycle-state-model.md`. Acceptance and publication of
owning-layer results and evidence are defined in
`simulation/docs/shared/checkpoint-acceptance-protocol.md`. Terminal presentation is
defined in `simulation/docs/shared/terminal-output.md`.

## Lifecycle Documentation Boundary

Shared lifecycle contracts do not live in backend documents:

| Document | Lifecycle responsibility |
| --- | --- |
| `simulation/docs/shared/simulation-model.md` | Shared public command semantics and operator workflow |
| `simulation/docs/shared/lifecycle-state-model.md` | Exact state, checkpoint order, guards, transitions, and recovery rights |
| `simulation/docs/shared/checkpoint-acceptance-protocol.md` | Owning-result and evidence acceptance plus checkpoint publication |
| `simulation/docs/shared/harness-design.md` | Shared architectural and dependency boundaries |
| `simulation/docs/shared/terminal-output.md` | Shared terminal presentation conventions |
| `simulation/docs/docker/docker-simulation.md` | Accepted Docker syntax, resource mechanisms, transport, and cleanup tools |
| `simulation/docs/docker/implementation-design.md` | Docker module boundaries and dependency direction |
| `simulation/docs/vm/vm-simulation.md` | Accepted VM syntax, resource mechanisms, transport, and cleanup tools |
| `simulation/docs/vm/implementation-design.md` | VM module boundaries and provisioning decisions |
| `simulation/docs/vm/command-sequences.md` | VM command flow through internal capabilities |
| `simulation/docs/vm/milestone-verification.md` | VM milestone pass/fail gates |
| `simulation/docs/vm/decisions/` | Narrow VM implementation decisions |

Backend documents apply these contracts and describe only their realization
deltas. They must not restate shared guards, statuses, resume rules, checkpoint
predecessors, input publication, or recovery sequences.

The model has two layers:

1. Docker-based simulation first, owned by
   `simulation/docker/simulate.sh`.
2. VM-based simulation second.

Both layers use the same five-machine topology:

| Machine/environment | Docker form | VM form | Responsibility |
| --- | --- | --- | --- |
| Bundle factory | Container | VM | Runs role helper `prepare-artifacts` commands and produces curated application artifacts, plugins, manifests, and checksums. |
| LDAP | Container | VM | Hosts LDAP bind, admin, and test accounts and groups. |
| Gerrit | Container | VM | Runs Gerrit with LDAP authentication, SSH access, integration permissions, and the `Verified` label. |
| Jenkins controller | Container | VM | Runs Jenkins, LDAP/JCasC configuration, Gerrit Trigger, and agent registration. |
| Jenkins agent | Container | VM | Runs SSH build jobs scheduled by Jenkins. |

## Shared Terminology And Backend Mapping

Use the shared terms in lifecycle contracts, command summaries, evidence, and
cross-backend plans. Use Docker or libvirt terms only when describing the
concrete backend mechanism.

| Recommended term | Meaning |
| --- | --- |
| Simulation set | One reusable backend environment selected by `HARNESS_SET_ID`. It owns durable runtime, baseline state, backend resources, and one active-run pointer. |
| Run | One immutable setup and validation attempt selected by `HARNESS_RUN_ID`. |
| Active run | The run referenced by the simulation set's non-secret `active-run.env` pointer. |
| Set root | Backend-local generated storage for reusable resources, durable runtime, baseline metadata, and the active-run pointer. |
| Run root | Backend-local generated storage for one run's inputs, checkpoints, evidence, logs, and exported artifacts. |
| Workflow state | The selected run's mutable checkpoint head in `workflow-state.env`; it cannot claim a set without a matching active-run pointer. |
| Source inputs | Actor-selected simulation env templates and supported overrides snapshotted by `init-run`. |
| Effective inputs | Stable helper env files rendered and atomically published by the first successful `start`. |
| Live target access | Backend-assigned transport addresses and verified SSH access refreshed by every `start`; not persistent input authority. |
| Exact bound | Durable state whose ownership, baseline, source and effective inputs, and completed checkpoint chain all agree with no open target mutation. |
| Durable runtime | State preserved by `stop` and reset only by `restore-baseline`. |
| Baseline | The set-owned clean pre-setup state used by `restore-baseline`. |

The two backends realize the same concepts differently:

| Shared concept | Docker realization | VM realization |
| --- | --- | --- |
| Simulation set | Compose-managed containers, network, project-built images, bind state, and baseline archives | Libvirt domains, networks, volumes, seed media, baked image, and baseline snapshots |
| Resource namespace | `loopforge-docker-<set-id>` Compose project | `loopforge-vm-<set-id>` libvirt prefix |
| Baseline | Checksummed image/Compose identity and bind-data archives | Checksummed VM metadata and clean disk snapshots |
| Durable runtime | Container writable layers and simulation-set bind data | Per-machine VM disks |
| Runtime definition | Retained Compose-created containers | Retained libvirt domain definitions |
| Running instance | Container processes | Running libvirt domains |

`HARNESS_SET_ID` and `HARNESS_RUN_ID` are the only shared operator-facing
simulation identities. `HARNESS_SET_ID` defaults to `default` when omitted in
either backend. It must contain 1-24 lowercase ASCII letters, digits, or
internal hyphens, start and end with a letter or digit, and is never normalized.
Derived backend namespaces are stable for the life of a simulation set, must
not include `HARNESS_RUN_ID`, and are recorded as backend resource metadata
rather than treated as additional operator identities. Length-limited hashed
names remain bound to full ownership metadata; collisions block.

## Harness Implementation Direction

Docker and VM simulation use separate public CLIs:
`simulation/docker/simulate.sh` and `simulation/vm/simulate.sh`. Do not
replace them with a single backend-dispatching entrypoint.

Shared implementation support belongs under `simulation/lib/` when code is
extracted. Extract only backend-neutral mechanics there: role parsing, env
loading, runtime input custody, command summaries, quoting helpers, artifact
manifest/checksum helpers, evidence helpers, and lifecycle marker utilities.

Layer lifecycle and transport stay local to each harness until real VM code
proves a stable boundary. Docker-specific Compose, image, container,
bind-mount, `docker cp`, loopback-port, and cleanup behavior belongs in the
Docker harness. VM-specific libvirt/KVM domains, resource groups, snapshots,
guest reboot, guest SSH readiness, guest-owned NFS-backed shared storage, and VM
`create`/`clean`/`destroy` behavior belongs in the VM harness.

Docker simulation may use explicit simulation-only waivers where containers
cannot naturally model target hosts. VM simulation is expected to be stricter:
libvirt/KVM provides the lab infrastructure, but lifecycle checkpoint work
should remain near target deployment and use target-like interfaces rather
than inheriting Docker shortcuts.

Do not introduce a Docker/VM backend abstraction before the VM harness has
enough implementation to prove a durable interface. Prefer small shared
support libraries first; if repeated backend-shaped code remains after the VM
harness is working, promote only that proven boundary.

## Simulation Accounts

The simulation model derives account roles and numeric identity policy from
`docs/contracts/account-model.md`. It does not introduce a separate account taxonomy.
Docker and VM simulation use the account model's example target-local names and
numeric identities by default unless a layer-specific configuration overrides
them.

Simulation targets provide a target-local `ci-operator` operator account with
passwordless sudo for simulation orchestration and privileged helper
operations. Privileged operations are still delegated privilege from the
operator account for narrow OS work; root is not a Loopforge account, helper
execution identity, runtime identity, or supported direct login identity. The
local host account that invokes a simulation `simulate.sh` may have any
site-local name and is not renamed, mapped, or required to be `ci-operator`.

Product runtime accounts own and run their simulated services: `gerrit` owns
`/srv/gerrit`, `jenkins` owns `/var/lib/jenkins`, and `jenkins-agent` owns
`/var/lib/jenkins-agent`. Jenkins controller and agent shared storage uses the
separate `jenkins-share` integration group from
`examples/integration.env.example`, not a shared controller/agent UID. The
default shared group is `jenkins-share` with no UID and GID `61040`. The
default shared path is `/data/jenkins-shared`; Docker models it with a
simulation-set-local bind mount, while VM simulation must model the target-deployment
shape by exporting it from the Jenkins agent VM and mounting it on the Jenkins
controller VM. `scripts/integration-setup.sh` owns creating or validating the
shared group, shared storage permissions, export or mount state, and
read/write proof.

Simulation LDAP seeds these human-style login accounts and groups for test
use only:

| Seeded entry | Type | Default credential | Purpose |
| --- | --- | --- | --- |
| `gerrit-admin` | LDAP user | `admin-password` | Gerrit administrator login. |
| `jenkins-admin` | LDAP user | `admin-password` | Jenkins administrator login. |
| `test-user` | LDAP user | `test-password` | Disposable Gerrit login and change workflow user. |
| `gerrit-admins` | LDAP group | none | Gerrit administrator group for seeded simulation users. |
| `jenkins-admins` | LDAP group | none | Jenkins administrator group for seeded simulation users. |
| `readonly` / `cn=readonly,dc=example,dc=test` | LDAP bind account | `readonly-password` | Read-only Gerrit and Jenkins directory search account. |

These credentials are simulation-owned fake test values. They must stay labeled
as simulation-only test credentials and must not be replaced with real
organization LDAP secrets.

Docker and VM `status` commands may print the seeded login accounts for their
simulation LDAP and product environments. The Jenkins Gerrit integration
account is different: it is created or validated later as a Gerrit service
account by the shared integration step, not seeded as an LDAP password user.

Docker and VM `ssh --role ROLE` commands intentionally use target OS
control-plane SSH as the target-local operator account. They are separate from
Gerrit's service SSH on port `29418` and from layer-specific backdoors such as
Docker exec or libvirt console access.

## Version Baseline

`docs/baselines/version-baseline.md` owns the default version baseline for both
simulation layers. Future verifiers must fail or report blocked rather than
claim comparable readiness when the Ubuntu, Java, Gerrit, Jenkins controller,
plugin-manager, or Jenkins agent/plugin-bundle versions differ from the
reviewed baseline.

## Source Boundaries

Ubuntu/OS dependencies and application artifacts are separate supply lanes.
Target hosts may use approved internal Ubuntu/OS package repositories for OS
dependencies. Application artifacts are prepared only in the bundle factory,
then staged to Gerrit, Jenkins controller, and Jenkins agent target/service
environments and verified by manifest and checksum before mutation.

Public internet fallback for target-host Ubuntu/OS dependency installation is
simulation-only and must be labeled `simulation-only` in docs, logs, and
verification summaries. Target hosts must not download Gerrit/Jenkins
application artifacts from the public internet as fallback. In v1, offline
Ubuntu dependency bundle workflows are not supported.

## Output Locations

Generated runtime output is not committed. Both backends store reusable
simulation-set state separately from immutable run output:

```text
generated/simulation/docker/sets/<set-id>/
generated/simulation/docker/locks/<set-id>.lock
generated/simulation/docker/<run-id>/
generated/simulation/vm/sets/<set-id>/
generated/simulation/vm/locks/<set-id>.lock
generated/simulation/vm/<run-id>/
```

Lifecycle and cleanup commands do not support arbitrary generated roots in
v1. `HARNESS_SET_ID` selects reusable resources and their baseline.
`HARNESS_RUN_ID` identifies one immutable attempt and is generated by
`init-run` when omitted. Simulation-set state persists across runs until
explicit destruction.

Docker uses these subpath patterns:

| Output kind | Generated pattern |
| --- | --- |
| Active-run pointer and baseline | `generated/simulation/docker/sets/<set-id>/` |
| Stable simulation-set lock | `generated/simulation/docker/locks/<set-id>.lock` |
| Workflow head and immutable checkpoint records | `generated/simulation/docker/<run-id>/host/state/` |
| Durable integration state | `generated/simulation/docker/sets/<set-id>/runtime/helper-state/` |
| Product runtime homes | `generated/simulation/docker/sets/<set-id>/runtime/product-homes/` |
| Staged artifacts | `generated/simulation/docker/sets/<set-id>/runtime/artifacts/staging/<role>/` |
| Exported artifacts | `generated/simulation/docker/<run-id>/target/artifacts/exported/<bundle>.tar.gz` |
| Harness evidence | `generated/simulation/docker/<run-id>/host/evidence/harness/` |
| Harness bounded logs | `generated/simulation/docker/<run-id>/host/logs/harness/` |
| Integration evidence and logs | `generated/simulation/docker/<run-id>/host/evidence/integration/`, `host/logs/integration/` |
| Target role evidence | `generated/simulation/docker/<run-id>/target/evidence/<role>/` |
| Target role bounded logs | `generated/simulation/docker/<run-id>/target/logs/<role>/` |

`<run-id>` uniquely identifies one validation attempt. Operators may supply it
for CI or audit workflows; normal interactive use lets `init-run` generate it.
`<environment>` is one of `bundle-factory`, `ldap`,
`gerrit`, `jenkins-controller`, or `jenkins-agent`.

These paths are generated runtime output unless a file in the tree states
otherwise. Keep them ignored or documented as generated when created by
simulation steps.

## Cleanup And Recovery

Simulation cleanup is manual and conservative. Cleanup commands remove
mutable generated runtime state for the selected run while preserving
the immutable run marker, checkpoint records, exported artifact archives,
evidence, and logs. Lifecycle commands that stop, reset, or destroy backend
resources are explicit and layer-owned; they must not silently discard review
evidence.

Never repair stale or inconsistent simulation state in place. Lifecycle
commands must fail clearly when selected generated state, container bind
mounts, simulation-set metadata, snapshots, or libvirt resources do not match
the selected run and reusable set. When exact ownership and baseline guards
still hold, recover with explicit `stop`, `restore-baseline`, and `clean`, then
let `init-run` generate a new run ID for the same set. Use ownership-validated
`destroy` only for reusable backend resource removal. When ownership cannot be
proved, select a fresh `HARNESS_SET_ID` and use an explicit migration or
separately approved host-level cleanup procedure for the old state.

Docker host-wide cleanup and VM host-wide libvirt cleanup remain separate
operator recovery paths. They are not selected-run baseline restoration or
generated-state cleanup.

`audit-state` is read-only inspection. `run`, role phases, integration
phases, and verification commands must not call cleanup, teardown,
destruction, or recovery implicitly.

### Docker And VM Lifecycle Mapping

Docker and VM simulation use different backend resources, but their lifecycle
commands preserve the same review and recovery boundaries:

| Concern | Docker simulation | VM simulation | Lifecycle meaning |
| --- | --- | --- | --- |
| External base artifact | Ubuntu/base Docker image | Source Ubuntu cloud image | External input or cache, not selected simulation ownership. |
| Reusable simulation artifact | Project-built Docker images | Set-local baked base image and baseline snapshots | Created or verified by `create`; removed by `destroy`. |
| Runtime definition | Compose-created retained containers | Libvirt domain definition | Both are established by `create` and removed by `destroy`. |
| Runtime instance | Container process/runtime | Running libvirt domain | `start` starts; `stop` stops without deleting the definition. |
| Persistent runtime filesystem | Container writable layers plus bind mounts | Per-machine VM disks | Preserved by ordinary `stop` and reset only by `restore-baseline`. |
| Fresh runtime from reusable artifact | Recreated containers plus restored checksummed bind data | VM disks restored from baseline snapshots | `restore-baseline` requires the selected simulation set to be stopped. |
| Generated host-side state | `generated/simulation/docker/<run-id>/` immutable run output | `generated/simulation/vm/<run-id>/` immutable run output | Mutable portions are removed by `clean`; retained review output remains. |
| Clean generated state | `clean` removes mutable generated run data | `clean` removes mutable generated run data | Does not reset Docker images or VM disks. |
| Reset durable runtime state | Recreate stopped containers from pinned images and restore the clean bind baseline | Reset VM disks to the clean baseline snapshot | `restore-baseline` does not clean generated state. |
| Remove reusable artifacts/resources | `destroy` removes selected containers, the harness network, and project-built images | `destroy` removes the selected simulation set's domains, disks, baked base image, seed media, networks, and metadata | Removes selected backend resources without deleting generated review output. |

| Goal | Docker sequence | VM sequence |
| --- | --- | --- |
| Start | `start` | `start` |
| Stop | `stop` | `stop` |
| Restart without cleaning generated state | `start -> stop -> start` | `start -> stop -> start` |
| Fresh durable runtime | `stop -> restore-baseline` | `stop -> restore-baseline` |
| Clean generated host-side state | `stop -> restore-baseline -> clean` | `stop -> restore-baseline -> clean` |
| Full rerun-oriented reset | `stop -> restore-baseline -> clean -> init-run -> start` | `stop -> restore-baseline -> clean -> init-run -> start` |
| Remove reusable backend artifacts | `stop -> destroy` | `stop -> destroy` |

## Shared Command Semantics

Backend simulation guides own the concrete command reference for their entrypoint.
When a layer uses these command names, the shared simulation semantics are:

| Command | Shared meaning |
| --- | --- |
| `run` | State-aware normal workflow composite. It initializes fresh state, resumes the exact active run at its next phase, or returns `already-complete`; it leaves the set running and never runs cleanup, restoration, destruction, or audit commands. |
| `preflight` | Read-only prerequisite check before service mutation. |
| `init-run` | Resolve `HARNESS_SET_ID` to `default` when omitted, generate a collision-resistant immutable `HARNESS_RUN_ID` when omitted or accept only an unused explicit value, snapshot selected source templates, write the source-bound run marker, and claim the selected set's active-run pointer with effective inputs pending. It rejects an active set or existing run root. |
| `create` | Create an absent claimed set and clean baseline, or verify an exact stopped existing set with non-mutating `state=existing`; running, unclaimed, restored, partial, drifted, or mismatched state blocks. |
| `start` | Start the selected simulation set without setup mutation, verify owned target access, refresh ephemeral transport values, and atomically publish stable effective inputs on the first successful start. Repeated start verifies rather than rewrites effective inputs; an exact running set returns `state=already-running`, and other state blocks. |
| `status` | Read-only inspection of coherent absent, unclaimed, stopped, or running state; contradictory state reports `conflicting` and exits nonzero. |
| `ssh` | Operator-account target OS control-plane SSH, not Gerrit service SSH. |
| `prepare-artifacts` | Artifact preparation through role helpers in the bundle factory. |
| `stage-artifacts` | Artifact transfer plus target-side manifest/checksum verification before service mutation. |
| `configure-role` | Role-local setup for one or all service roles, including establishing the role runtime. |
| `validate-role` | Observational role-local readiness validation only; it does not start, restart, enable, or repair a role runtime and makes no cross-role success claim. |
| `configure-integration` | Apply and validate ACLs as `simulation-only direct Gerrit REST apply`, then complete shared integration setup through `scripts/integration-setup.sh`; Reviewed Access is not supported. |
| `validate-integration` | Passive cross-role readiness validation. |
| `prove-integration` | Active end-to-end trigger proof after matching validation passed. |
| `audit-state` | Explicit read-only generated-state and simulation-set consistency inspection. |
| `stop` | Gracefully stop configured services and the selected simulation set while preserving durable state, source/effective input custody, and review output; live target access becomes unavailable. An ownership-valid stopped set returns `state=already-stopped`. |
| `restore-baseline` | Require a stopped simulation set and reset its durable runtime to the selected clean pre-setup baseline without cleaning generated state. |
| `clean` | After matching baseline restoration, clear mutable workflow/run state and remove the selected set's active-run pointer last while preserving the immutable run marker, checkpoint records, artifacts, evidence, logs, and baseline resources. |
| `destroy` | Ownership-validated backend resource deletion; a fully absent unclaimed set returns `state=already-absent`, while missing resources contradicted by metadata block. |

Layers may add simulation-specific lifecycle commands, such as VM `reboot`,
but unsupported or unavailable proof must fail closed or report blocked rather
than produce synthetic success. Docker does not expose `reboot` because it
does not claim guest reboot persistence.

`up` and `down` are removed command names. Layers must reject them rather than
retain aliases that hide the selected resource transition.

The simulation integration sequence is `integration-preflight`,
`configure-integration`, `validate-integration`, `prove-integration`, then
`evidence-audit`. It has no Reviewed Access checkpoint, wait, or resume path.

Set mutations use the stable nonblocking lock at
`generated/simulation/<backend>/locks/<set-id>.lock`; contention reports
`set busy`. The set-scoped `active-run.env` owns claim and reset gating. The
run-scoped `workflow-state.env` owns only checkpoint activity and progression.
Strict readers cross-check both records with the immutable run marker,
baseline, source/effective-input fingerprints, backend ownership, and
hash-linked checkpoint records. Details and exact transitions are authoritative
in `simulation/docs/shared/lifecycle-state-model.md`. Result and evidence acceptance
plus publication order are defined in
`simulation/docs/shared/checkpoint-acceptance-protocol.md`.

## Terminal Output Convention

`simulation/docs/shared/terminal-output.md` owns shared simulation terminal presentation
conventions, including compact command summaries and Docker/VM `status`
previews. Backend simulation guides own concrete command behavior for their
entrypoints.

## Input And Secret Handling

Simulation env examples are source templates. During `init-run`, harnesses
snapshot the selected harness, role, and integration templates plus supported
overrides under private run-scoped source-input custody. The first successful
`start` renders stable backend values, validates the complete helper env set,
and atomically publishes private effective inputs. The rendered harness record
is for inspection; private runtime config points at the effective files.

Role and integration phases transfer or consume the published effective files
without rewriting them. Backend-assigned transport hosts are refreshed after
every `start` and remain outside source and effective fingerprints. For
simulation integration only, a harness may create a private temporary copy of
the effective `integration.env`, overlay only the three current target SSH host
fields, invoke `scripts/integration-setup.sh` through its existing env-file
interface, and delete the temporary file. That invocation adapter is not
retained input state or evidence and does not apply to target deployment.

Input rendering and publication change host-side generated state only. They do
not authorize role or integration target mutation or complete a product
checkpoint. `stop` preserves source and effective input custody while making
live target access unavailable; a later `start` re-establishes and verifies
that access without rewriting the stable inputs.

Docker and VM simulation may use simulation-owned fake LDAP bind passwords for
their own LDAP environments. The default example values are not real
organization secrets and must not be replaced with real organization secrets.
They are copied into run-scoped inputs. Logs, evidence, and artifact bundles
must not expose secrets. Product runtime config files may still persist
product-required LDAP settings after the relevant role helper writes them.

Both simulation layers must realize LDAP as a simulation-owned directory
service with real bind/search behavior. They must not satisfy LDAP readiness
with modeled success or with real organization LDAP secrets.

## Harness And Helper Boundary

Simulation harnesses provide the environment work they must provide: generated
run roots, source/effective input custody, environment lifecycle, network or SSH
control-plane access, and explicitly labeled simulation transfer waivers.
Role helpers still own role-local lifecycle work inside helper-visible paths,
including creation of `/var/lib/loopforge` and `/var/log/loopforge`, artifact
preparation, target-local mutation, validation, and evidence collection.

Artifact preparation writes role artifacts and archive pairs in the bundle
factory. Artifact staging transfers archive pairs to target environments
through a layer-specific, labeled transfer mechanism, then verifies manifest
and checksum data on the target side under `/var/lib/loopforge/staging`
before service mutation. Simulation backing paths and transfer mechanisms may
support this lifecycle, but helper-visible paths remain product-like.

Initial target operations install native product-owned paths such as
`/srv/gerrit`, `/var/lib/jenkins`, `/var/lib/jenkins-agent`,
`$JENKINS_HOME/.ssh/known_hosts`, and agent `authorized_keys`. Transient
target-local files under `/tmp` are acceptable when they stage payloads for
normal target APIs or runtime installation, but they must not bypass published
effective helper inputs or helper-owned state.

Generated evidence, logs, and exported artifacts may be collected for review.
Jenkins-owned private keys under integration key storage are the deliberate
exception to host-side custody: the Jenkins controller owns Jenkins-to-Gerrit
and Jenkins-to-agent private keys, while generated scripts, status files,
evidence, and public-key metadata remain harness or integration sideband
state.

## State Consistency And Recovery

Exact consistency dimensions, classifications, guards, and recovery rights are
defined only in `simulation/docs/shared/lifecycle-state-model.md`. Public commands fail
closed on inconsistent selected state and never repair it implicitly. Docker
and VM documents add only the backend resource probes used to apply that model.

## Lifecycle Realization

`docs/contracts/lifecycle-contract.md` defines product checkpoint semantics and
mutation boundaries. The state model maps those checkpoints into the simulation
workflow, and the acceptance protocol defines how owning results enter it.
Backend orchestration invokes the same role and integration owners through its
documented transport; it does not create another lifecycle contract.
