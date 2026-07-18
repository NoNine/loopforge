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
`simulation/docs/harness-design.md` and
`simulation/docs/lifecycle-state-model.md`. Cross-layer checkpoint ownership
and publication are defined in
`simulation/docs/checkpoint-coordination.md`. Docker generated-state and stale-
container behavior is defined in this document.
Docker-local module boundaries and dependency direction are defined in
`simulation/docker/docs/implementation-design.md`.

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

This section owns Docker command behavior. The command-to-checkpoint mapping
is summarized in `docs/contracts/lifecycle-contract.md`.

Composite command:

| Command | Purpose |
| --- | --- |
| `run [--env FILE]` | Initializes fresh state or resumes the exact active immutable run at its next required phase, leaving the set running. An exact completed run returns `already-complete`; interrupted, conflicting, restored, run-ID-mismatched, or input-changed state blocks. It does not run `stop`, `restore-baseline`, `clean`, `destroy`, or `audit-state`. |
| `ssh [--env FILE] --role ROLE` | Opens an interactive host-to-target OS SSH session using the published effective target inventory verified by `start`. This is for target OS access as the operator account, not Gerrit service SSH. |

Phase and lifecycle commands:

| Command | Purpose |
| --- | --- |
| `preflight [--env FILE]` | Validates required tools, Compose availability, static harness files, baseline labels, and script wiring. Terminal output is a short `preflight: ok ...` summary; details stay in generated evidence. |
| `init-run [--env FILE]` | Resolves `HARNESS_SET_ID`, generates `HARNESS_RUN_ID` when omitted, rejects an existing run root or active simulation set, snapshots selected source templates, writes source-bound run state, and claims the set with effective inputs pending. |
| `create [--env FILE]` | Builds and creates an absent claimed set, captures its clean baseline, and leaves it stopped. For an exact stopped existing set it verifies set metadata and returns non-mutating `state=existing`; running, unclaimed, restored, partial, drifted, unowned, or mismatched state blocks. |
| `start [--env FILE]` | Starts the exact retained containers, verifies published target access, and atomically renders stable effective inputs on the first successful start. From baseline state it starts environment prerequisites only; from exact-bound state it also starts already-configured Gerrit and Jenkins without rewriting configuration. Repeated start verifies rather than rewrites effective inputs. An exact running set returns `state=already-running`; other state blocks. |
| `status [--env FILE]` | Reports coherent absent, unclaimed, stopped, or running Docker state, including set/run identity, durable classification, reset gate, and live access data when available. Contradictory state reports `conflicting` and exits nonzero. |
| `prepare-artifacts [--env FILE] [--role ROLE]` | Runs one role, or all Docker roles when `--role` is omitted, inside the bundle factory and exports bundle archives plus checksums. Success prints compact `prepare-artifacts[role]: ok` summaries. |
| `stage-artifacts [--env FILE] [--role ROLE]` | Verifies exported bundle archives, copies the archive pair into the target container with a Docker simulation-only `docker cp` waiver, extracts to `/var/lib/loopforge/staging/gerrit`, `/var/lib/loopforge/staging/jenkins`, or `/var/lib/loopforge/staging/jenkins-agent`, and checks manifests/checksums before mutation. Success prints compact `stage-artifacts[role]: ok` summaries. |
| `configure-role [--env FILE] [--role ROLE]` | Runs one role-local configuration phase, or all Docker roles when `--role` is omitted, against the target container, establishes the applicable Gerrit or Jenkins process, and records evidence. Success prints `configure-role[role]: ok`; failures include `log=` and `evidence=`. |
| `validate-role [--env FILE] [--role ROLE]` | Observes one role-local runtime, or all Docker roles when `--role` is omitted, against the target container and records evidence. It does not start or repair a process. Success prints `validate-role[role]: ok`; failures include `log=` and `evidence=`. |
| `configure-integration [--env FILE]` | Configures shared integration state for Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, shared storage, and the Gerrit Trigger server. Success prints a short `configure-integration: ok` summary. |
| `validate-integration [--env FILE]` | Runs passive cross-role readiness validation and writes a marker for later verification. Success prints a short `validate-integration: ok` summary. |
| `prove-integration [--env FILE]` | Requires a matching successful validate marker for the same run, then runs the active cross-role proof. It does not run `validate-integration` implicitly. Success prints a short `prove-integration: ok` summary. |
| `audit-state [--env FILE]` | Performs the explicit Docker container and bind-mount sweep for the selected run. It is read-only and does not rerun other phases. |
| `stop [--env FILE]` | Gracefully stops configured Gerrit and Jenkins runtimes, then stops the exact containers without removing them. An ownership-valid stopped set returns `state=already-stopped` with its durable classification and reset gate. |
| `restore-baseline [--env FILE]` | Requires stopped owned containers, verifies the baseline manifest, recreates containers from the pinned images and Compose definition, restores the clean checksummed bind baseline and target SSH identity, and leaves the environment stopped. |
| `clean [--env FILE]` | Requires the simulation set to be stopped and successfully restored, deletes mutable workflow/run state, and removes the set's active-run pointer last. It preserves the immutable run marker, checkpoint records, review output, Docker baseline, and reusable resources. |
| `destroy [--env FILE]` | Removes ownership-validated selected containers, network, project-built images, baseline, set metadata, and active pointer. A fully absent unclaimed set returns `state=already-absent`; contradictory ownership or resource state blocks. |

`ROLE` is one of `gerrit`, `jenkins-controller`, or `jenkins-agent`.

## Input Model

If `--env FILE` is omitted, the harness uses
`simulation/docker/examples/docker.env.example` as the bootstrap env file.
Copy that file outside committed examples before using real operator values.

The harness env file must identify role and integration env inputs:

```text
HARNESS_GERRIT_ENV_FILE=examples/gerrit.env.example
HARNESS_JENKINS_CONTROLLER_ENV_FILE=examples/jenkins-controller.env.example
HARNESS_JENKINS_AGENT_ENV_FILE=examples/jenkins-agent.env.example
HARNESS_INTEGRATION_ENV_FILE=examples/integration.env.example
```

During `init-run`, the selected harness, role, and integration templates are
copied to `generated/simulation/docker/<run-id>/host/source-inputs/` with mode
`0600`, and their fingerprint is bound to the run marker. The first successful
`start` renders and atomically publishes stable effective helper files under
`host/runtime-inputs/` plus `host/state/effective-inputs.env`. Later commands
verify both bindings before operating, and no workflow phase rewrites the
effective files.

`HARNESS_SET_ID` is the stable reusable simulation-set identity and defaults
to `default` when omitted. It must contain 1-24 lowercase ASCII letters,
digits, or internal hyphens and start and end with a letter or digit; the
harness rejects rather than normalizes other values.
`HARNESS_RUN_ID` identifies one immutable attempt; `init-run` generates it when
omitted, while an explicit value must not already exist. The simulation set
stores one non-secret `active-run.env` pointer. `stop` and `start` preserve it.
Only successful `clean` or set destruction removes it before another generated
run ID can claim the same set.

The Docker harness derives the Compose project name exactly as
`loopforge-docker-<set-id>`. That injective name is backend resource metadata,
remains stable across runs of the set, and must not include `HARNESS_RUN_ID` or
act as another operator identity.

`harness.env` is the rendered harness record for inspection. The private
`harness.runtime.env` retains lifecycle values and points at the runtime input
copies. Non-secret run markers and manifest contracts are public/read-only
metadata, not secret material.

For v1, Docker simulation does not support arbitrary generated/output roots.
Reusable resources and run output use these repo-local roots:

```text
generated/simulation/docker/sets/<set-id>/
generated/simulation/docker/locks/<set-id>.lock
generated/simulation/docker/<run-id>/
```

## Simulation Accounts

The shared simulation account contract, including seeded LDAP login accounts,
is defined in `simulation/README.md`. The Docker target image realizes that
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

Use `simulate.sh status --env FILE` to inspect the selected set in absent,
unclaimed, stopped, or running state. The status command prints the set ID,
active run when present, derived Compose project name, durable classification,
and reset gate. It prints live browser URLs and seeded login accounts only
when the running state can prove them; it does not substitute stale rendered
port data.

Use `simulate.sh ssh --role ROLE` after `start` to log into a target OS
environment as the target-local `ci-operator` through SSH from the host. The
command uses the published effective `INTEGRATION_*_TARGET_SSH_*` values and
the run-scoped target SSH key and known-hosts file:

```bash
simulation/docker/simulate.sh ssh --role gerrit
simulation/docker/simulate.sh ssh --role jenkins-controller
simulation/docker/simulate.sh ssh --role jenkins-agent
```

This command intentionally uses the target OS control-plane SSH interface. It
does not use Docker exec and it is separate from Gerrit's service SSH on port
`29418`.

## Output Locations

Docker-generated runtime output is not committed. Reusable simulation-set state and
immutable run output use separate roots:

```text
generated/simulation/docker/sets/<set-id>/
generated/simulation/docker/<run-id>/
```

| Output kind | Docker generated pattern |
| --- | --- |
| Active-run pointer and baseline | `generated/simulation/docker/sets/<set-id>/` |
| Stable set lock | `generated/simulation/docker/locks/<set-id>.lock` |
| Workflow head and checkpoint records | `generated/simulation/docker/<run-id>/host/state/` |
| Durable bind state | `generated/simulation/docker/sets/<set-id>/runtime/` |
| Host-contributed inputs | `generated/simulation/docker/<run-id>/host/` |
| Exported artifacts | `generated/simulation/docker/<run-id>/target/artifacts/exported/<bundle>.tar.gz` |
| Harness evidence | `generated/simulation/docker/<run-id>/host/evidence/harness/` |
| Harness bounded logs | `generated/simulation/docker/<run-id>/host/logs/harness/` |
| Integration evidence and logs | `generated/simulation/docker/<run-id>/host/evidence/integration/`, `host/logs/integration/` |
| Target role evidence | `generated/simulation/docker/<run-id>/target/evidence/<role>/` |
| Target role bounded logs | `generated/simulation/docker/<run-id>/target/logs/<role>/` |

Implementation-specific harness state can live below child directories inside
those roots. Shared simulation contracts for input custody, helper-visible paths,
artifact staging, LDAP secret handling, retained outputs, and integration key
custody live in `simulation/README.md`, `docs/contracts/artifact-bundle-contract.md`,
and `docs/contracts/directory-model.md`.

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

`stop`, `restore-baseline`, and `clean` are deliberately separate. `stop` uses
Docker Compose stop behavior and preserves containers, writable layers, bind
data, active-run ownership, and generated output. `restore-baseline` is the explicit durable reset;
it may recreate only the stopped ownership-validated selected containers and
restore only the selected checksummed bind baseline. `clean` clears active-run
ownership and mutable run state but does not reset containers or bind data.

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

`clean` follows the shared retained-output contract from
`docs/contracts/directory-model.md`. It verifies the selected run marker and operates
only under the canonical repo-local generated run root. It leaves retained
review output, the immutable run marker, and checkpoint completion records
under that immutable root and removes runtime inputs, the mutable workflow
head, target SSH client material, and the set active-run pointer last. Durable
product homes, LDAP data, shared storage, stopped
container layers, and baseline state belong to `restore-baseline`, not
`clean`. If the host user cannot remove
container-owned generated files, `clean` may use a one-shot cleanup container
mounted only to the validated generated-state paths.

See `docs/contracts/lifecycle-contract.md` for phase behavior rules and
`docs/contracts/directory-model.md` for generated path ownership and
host/target dominance.

## State Consistency And Recovery

Docker state follows the shared run-consistency contract from
`simulation/README.md` and adds Compose and bind-mount checks. The selected
Compose project identifies these expected service containers:

- `bundle-factory`
- `ldap`
- `gerrit-target`
- `jenkins-controller-target`
- `jenkins-agent-target`

Containers exist when any expected service container for the selected Compose
project exists, whether it is running or stopped. Docker consistency additionally
requires these Docker-specific generated paths and bind sources:

- The canonical run root exists under `generated/simulation/docker/<run-id>/`.
- The selected set root exists under
  `generated/simulation/docker/sets/<set-id>/` and its active-run
  pointer matches the run marker.
- The strict run-scoped `workflow-state.env`, effective-input record, and
  hash-linked checkpoint records match the pointer, marker, baseline, and
  source/effective input fingerprints.
- When workflow input state is `ready`, the flat effective helper env bundle
  under `host/runtime-inputs/` and its strict effective-input record exist and
  match their published fingerprints.
- Expected generated bind source directories exist before container lifecycle
  phases use them.

When selected containers already exist, resume/rerun phases also validate that
container bind mounts still point at the selected simulation-set runtime root. A host
probe written to each required bind source must be visible at the expected
container destination before a phase relies on that mount.

If generated state, container identity, or bind-mount liveness is inconsistent,
lifecycle phases fail clearly instead of recreating state or rerunning earlier
phases. Inspect with `audit-state`; use `stop`, `restore-baseline`, `clean`, or
ownership-checked `destroy` according to the failed state boundary.

| Situation | Expected behavior |
| --- | --- |
| No selected resources and no baseline | `init-run` creates or accepts a unique run ID; `create` establishes the reusable stopped environment and clean baseline. |
| Exact stopped existing baseline | `create` verifies set-scoped metadata and returns non-mutating `state=existing`. |
| Running selected resources | `create` blocks and requires `stop`. |
| Stopped selected containers and matching generated/baseline state | `start` may continue after validating container, bind, active-run, and checkpoint state. |
| Exact selected containers already running | `start` returns non-mutating `state=already-running`. |
| Ownership-valid selected containers already stopped | `stop` returns non-mutating `state=already-stopped` without claiming workflow health. |
| Running selected containers and exact-bound state | `stop` gracefully stops services and retains all durable state. |
| Stopped exact-bound state | `start` starts the already-configured services without setup mutation. |
| Stopped selected containers with a valid baseline | `restore-baseline` may recreate only those containers and restore only selected bind data. |
| The selected simulation set has an active run | `init-run` fails; use `stop`, `restore-baseline`, and `clean` before generating another run ID. |
| Partial or inconsistent state | Normal phases and `start` fail clearly; recovery commands operate only when their ownership prerequisites can be proved. |

`stop` must not remove containers or the selected network. When configuration
is exact and complete, it uses native Gerrit and Jenkins stop operations before
Compose stop so container shutdown does not become an ungraceful application
reset. From baseline state it stops prerequisites only.

`restore-baseline` is the only normal selected-run command that may remove and
recreate containers. It must reject running containers, image/Compose drift,
an invalid baseline manifest, unowned resources, or target SSH identity drift.

`audit-state` is the explicit read-only command for the expensive container
and bind-mount sweep. It checks live selected containers against the selected
run root for operator inspection and is not part of the default path for
normal lifecycle phases.

Typical flows:

```bash
simulation/docker/simulate.sh --env FILE init-run
simulation/docker/simulate.sh --env FILE create
simulation/docker/simulate.sh --env FILE start
simulation/docker/simulate.sh --env FILE configure-role
simulation/docker/simulate.sh --env FILE validate-role
simulation/docker/simulate.sh --env FILE configure-integration
simulation/docker/simulate.sh --env FILE validate-integration
simulation/docker/simulate.sh --env FILE prove-integration
simulation/docker/simulate.sh --env FILE stop
simulation/docker/simulate.sh --env FILE restore-baseline
simulation/docker/simulate.sh --env FILE clean
simulation/docker/simulate.sh --env FILE destroy
```

Use `configure-role` and `validate-role` for role-local work only. Use
`validate-integration` for passive cross-role readiness and
`prove-integration` only after `validate-integration` has already passed for
the same initialized run.
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

`up` and `down` are unsupported command names. The CLI must reject them and
must not provide compatibility aliases.

## Integration Boundary

The shared integration boundary is defined in `simulation/README.md` and
`docs/contracts/lifecycle-contract.md`. Docker orchestrates that shared helper through
the Docker target SSH inventory and generated Docker run state.

`validate-integration` and `prove-integration` must fail or report blocked
rather than claim Docker readiness when real integration proof is unavailable.
Forbidden synthetic success markers in role or integration logs are treated as
failures.

Source-boundary rules, including simulation-only public internet fallback for
target-host Ubuntu/OS dependency installation, are shared in
`simulation/README.md`.
