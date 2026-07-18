# Docker Simulation

Docker simulation is the first executable simulation layer for the v1
Gerrit/Jenkins setup package. The single Docker entrypoint is:

```bash
simulation/docker/simulate.sh <command>
simulation/docker/simulate.sh [--env FILE] <command>
```

`simulate.sh` owns role-local gates and cross-role integration
orchestration. Do not add standalone Docker phase scripts or a second Docker
verifier CLI.

Docker simulation is the executable reference harness. It may source shared
support helpers from `simulation/lib/` after they exist, but that extraction
must preserve Docker command behavior. Docker-specific Compose selection,
container lifecycle, bind-mount validation, `docker cp` waivers, loopback
browser ports, target SSH staging, and cleanup behavior remain Docker harness
responsibilities rather than generic backend hooks.

Lifecycle checkpoint semantics are defined in `docs/contracts/lifecycle-contract.md`.
Shared harness architecture and exact state guards are defined in
`simulation/docs/shared/harness-design.md` and
`simulation/docs/shared/lifecycle-state-model.md`. Cross-layer result acceptance and
checkpoint publication are defined in
`simulation/docs/shared/checkpoint-acceptance-protocol.md`. Docker generated-state and
stale-container behavior is defined in this document.
Docker-local module boundaries and dependency direction are defined in
`simulation/docs/docker/implementation-design.md`.

The shared Docker target image is a simulation superset. It combines
role-runtime packages, helper-script packages, and Docker harness packages; it
is not authority for native target-host baselines. See
`docs/baselines/package-requirements.md` for the package classification.
Docker-specific service names, host loopback browser URLs, and target SSH
inventory values follow `docs/contracts/endpoint-identity.md`.

Docker does not run a guest init system. Its target containers retain the
existing direct-process lifecycle: the container entrypoint starts `sshd`, and
Gerrit and Jenkins use the existing role-process mechanism. Do not add
systemd, a container supervisor, restart policies, or Compose lifecycle work
as part of the guest service lifecycle contract. Docker does not claim
guest-reboot persistence and does not expose a `reboot` command.

`configure-role` must establish a role runtime before `validate-role` runs.
`validate-role` is observational and must fail for a missing or inactive
process rather than start or repair it. Current Docker helper alignment with
this phase boundary is pending implementation.

## Command Reference

Shared command meanings and state outcomes are authoritative in
`simulation/docs/shared/simulation-model.md` and `simulation/docs/shared/lifecycle-state-model.md`. Docker
accepts that command surface through `simulation/docker/simulate.sh`; this
section lists only Docker syntax and realization deltas.

Docker adds no backend-only command or operand to the shared command surface.

| Command scope | Docker realization |
| --- | --- |
| `preflight` | Checks Docker tooling, Compose availability, images, static harness files, and Docker wiring |
| `create`, `start`, `stop`, `status` | Operate on retained Compose containers, bind data, loopback ports, and published target access |
| `ssh` | Opens target-container OS SSH as the simulation operator account |
| `prepare-artifacts` | Runs role helpers in the bundle-factory container and exports review archives |
| `stage-artifacts` | Uses the labeled `docker cp` waiver, then verifies target-container manifests and checksums |
| Role and integration phases | Invoke the shared owners through Docker target access and publish results through the shared checkpoint protocol |
| `audit-state` | Adds an explicit container, network, image, port, and bind-mount consistency sweep |
| `restore-baseline` | Recreates selected stopped containers and restores checksummed bind archives from the Docker baseline |
| `clean` | May use a restricted one-shot container to remove validated container-owned mutable generated files |
| `destroy` | Removes only ownership-validated selected containers, network, project-built images, baseline, and set metadata |

## Input Model

If `--env FILE` is omitted, the harness uses
`simulation/docker/examples/docker.env.example` as the bootstrap env file.

Source/effective input custody, set/run identity, and publication behavior are
shared contracts in `simulation/docs/shared/simulation-model.md` and the lifecycle state model. The
Docker harness consumes those records without a backend-local input lifecycle.

The Docker harness derives the Compose project name exactly as
`loopforge-docker-<set-id>`. That injective name is backend resource metadata,
remains stable across runs of the set, and must not include `HARNESS_RUN_ID` or
act as another operator identity.

Docker renders stable loopback endpoint values into the shared effective input
bundle. Current published ports and target SSH access remain live backend
state and are verified before use.

## Simulation Accounts

The shared simulation account contract, including seeded LDAP login accounts,
is defined in `simulation/docs/shared/simulation-model.md`. The Docker target image realizes that
contract with the default simulation operator and product runtime accounts.
During `create`, the clean baseline initializes empty bind-mounted product-home
roots to the baked runtime accounts' reviewed numeric ownership. Later
`start` operations validate ownership without changing it. Drift blocks and
requires `stop` plus `restore-baseline`; the harness does not repair populated
product homes during normal startup.

Docker realizes Jenkins shared storage by bind-mounting one simulation-set-local
`runtime/shared-jenkins-storage` directory into both the Jenkins controller and
Jenkins agent containers at `JENKINS_SHARED_STORAGE_PATH`, normally
`/data/jenkins-shared`. `configure-integration` applies the shared
`jenkins-share` group, setgid group-writable permissions, and read/write proof
inside those containers.

## Generated-State Realization

`simulation/docs/shared/generated-state-layout.md` owns the common set, lock,
and run roots plus their custody and cleanup classes. Docker adds reusable bind
state under `sets/<set-id>/runtime/`, baseline archives and metadata under
`sets/<set-id>/baseline/`, and Docker transfer material in the documented
run-root children. Backend implementation scratch may live below those
backend-owned children without becoming a new public path contract.

Shared simulation contracts for input custody, helper-visible paths, artifact
staging, LDAP secret handling, retained outputs, and integration key custody
live in `simulation/docs/shared/generated-state-layout.md`,
`simulation/docs/shared/simulation-model.md`,
`docs/contracts/artifact-bundle-contract.md`, and
`docs/contracts/directory-model.md`.

Docker realizes those contracts with container lifecycle, generated bind-mount
sources, and explicitly labeled Docker `cp` waivers:

- Role helper roots `/var/lib/loopforge` and `/var/log/loopforge` are not
  Docker bind mounts in role containers.
- `prepare-artifacts` exports bundle archive pairs from the bundle factory to
  `target/artifacts/exported/` through the harness collector.
- `stage-artifacts` copies archive pairs into target containers with a Docker
  simulation-only `docker cp` waiver, then extracts and verifies them under
  `/var/lib/loopforge/staging`.
- Effective helper env files remain under `host/runtime-inputs/`; Docker
  copies them to `/home/ci-operator/loopforge-inputs` with a labeled Docker
  `cp` input waiver before helper execution.
- The run-scoped target SSH public key is staged as Docker control-plane input
  and installed as the target-local `ci-operator` `authorized_keys` file during
  `start`; the private key remains only under `host/target-ssh/`.
- The host collector copies bounded evidence and logs from containers with a
  labeled Docker `cp` collector waiver.

## Cleanup Contract

Host-wide Docker recovery is available as a separate operator tool:

```bash
simulation/docker/tools/cleanup-docker-resources.sh --dry-run
simulation/docker/tools/cleanup-docker-resources.sh --destroy
```

The dry run inventories LoopForge Docker simulation containers, Compose
`harness` networks, and project-built images discoverable from Docker Compose
labels plus exact project/service image names. It prints the ordered removal
actions without mutation. No-option execution is also a dry run. Actual
cleanup uses `--destroy`, removes matching containers first, then networks,
then project-built images, and fails if matching resources remain. It does not
remove generated workspaces, bind-mounted data, base images, artifacts,
evidence, or logs. This is a host-wide recovery tool, not selected-run
`stop`, `restore-baseline`, `clean`, or `destroy` behavior.

Shared stop, restore, clean, and destroy rights are defined in the lifecycle
state model. Docker realizes them with Compose stop, selected-container
recreation, checksummed bind restoration, and ownership-validated resource
deletion.

The Docker baseline lives under the selected simulation-set root and contains a
manifest binding image digests, Compose config digest, bind archive digests,
numeric ownership, target SSH identity, set identity, derived Compose project
name, and implementation revision.
It contains clean LDAP data, empty product homes, and empty shared storage from
before artifact staging or setup. It must not contain real organization setup
credentials,
private integration keys, application configuration, or proof artifacts. The
clean LDAP archives may contain the documented simulation-owned fake LDAP
credential state required to restore that directory service; they must not be
used with real organization credentials.

Retained-output and mutable-cleanup classes come from
`simulation/docs/shared/generated-state-layout.md`. If the host user cannot remove a validated
container-owned mutable path, Docker `clean` may use a one-shot cleanup
container mounted only to that generated-state path.

See `docs/contracts/lifecycle-contract.md` for phase behavior rules and
`simulation/docs/shared/generated-state-layout.md` for generated path custody
and host/target dominance.

## State Consistency And Recovery

Docker applies the shared state model by adding Compose and bind-mount probes.
The selected Compose project identifies these expected service containers:

- `bundle-factory`
- `ldap`
- `gerrit-target`
- `jenkins-controller-target`
- `jenkins-agent-target`

Containers are present when any expected service container exists, whether it
is running or stopped. Docker additionally verifies image and Compose identity,
selected labels, expected bind sources, and container mounts. Before a phase
uses a bind, a host probe in its validated source must be visible at the
expected container destination.

`stop` must not remove containers or the selected network. When configuration
is exact and complete, it uses native Gerrit and Jenkins stop operations before
Compose stop so container shutdown does not become an ungraceful application
reset. From baseline state it stops prerequisites only.

Docker baseline restoration rejects running containers, image or Compose
drift, an invalid baseline manifest, unowned resources, and target SSH identity
drift before container recreation.

`audit-state` is the explicit read-only command for the expensive container
and bind-mount sweep. It checks live selected containers against the selected
run root for operator inspection and is not part of the default path for
normal lifecycle phases.

Use `audit-state` when you need the slower bind-mount audit for an existing
run. Normal lifecycle phases keep the cheap runtime-config check only.

Docker `destroy` removes only selected LoopForge-labeled Docker resources for
the selected simulation set: containers, the harness network, and
project-built images. It may recover the derived Compose project name from
ownership-valid set metadata when rendered runtime state has been removed; set
identity alone never authorizes deletion. It leaves
upstream/base images such as `HARNESS_UBUNTU_IMAGE` and `HARNESS_LDAP_IMAGE`
intact, removes the selected baseline state, and leaves retained run output for
review.

## Integration Boundary

Docker invokes the shared integration owner through the Docker target SSH
inventory and private invocation adapter. Integration checkpoint semantics,
predecessors, evidence acceptance, and failure behavior remain shared.

Source-boundary rules, including simulation-only public internet fallback for
target-host Ubuntu/OS dependency installation, are shared in
`simulation/docs/shared/simulation-model.md`.
