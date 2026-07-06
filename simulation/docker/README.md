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

Lifecycle checkpoint semantics are defined in `docs/lifecycle-contract.md`.
Docker generated-state and stale-container behavior is defined in this
document.

The shared Docker target image is a simulation superset. It combines
role-runtime packages, helper-script packages, and Docker harness packages; it
is not authority for native target-host baselines. See
`docs/package-requirements.md` for the package classification.
Docker-specific service names, host loopback browser URLs, and target SSH
inventory values follow `docs/endpoint-identity.md`.

## Command Reference

This section owns Docker command behavior. The command-to-checkpoint mapping
is summarized in `docs/lifecycle-contract.md`.

Composite command:

| Command | Purpose |
| --- | --- |
| `run [--env FILE]` | Runs the normal Docker simulation workflow. It reports whether the run is `fresh` or `resume`, then executes `preflight` through `prove-integration`. It does not run `down`, `clean`, or `audit-state`. |
| `ssh [--env FILE] --role ROLE` | Opens an interactive host-to-target OS SSH session using the rendered Standard Interfaces target inventory. This is for target OS access as the operator account, not Gerrit service SSH. |

Phase and lifecycle commands:

| Command | Purpose |
| --- | --- |
| `preflight [--env FILE]` | Validates required tools, Compose availability, static harness files, baseline labels, and script wiring. Terminal output is a short `preflight: ok ...` summary; details stay in generated evidence. |
| `init-run [--env FILE]` | Loads the bootstrap env file, copies the harness, role, and integration env inputs into private run-scoped runtime inputs, resolves browser ports, writes rendered/runtime env files, and writes the artifact manifest contract. Terminal output is a short `init-run: ok run-id=...` summary. |
| `up` | Starts the bundle factory, LDAP, Gerrit target, Jenkins controller target, and Jenkins agent target containers. Success prints one short `up: started ...` summary. |
| `status [--env FILE]` | Requires the selected run's containers to be running, inspects live published browser ports, and prints run identity, browser URLs, and Docker simulation login accounts. |
| `prepare-artifacts [--env FILE] [--role ROLE]` | Runs one role, or all Docker roles when `--role` is omitted, inside the bundle factory and exports bundle archives plus checksums. Success prints compact `prepare-artifacts[role]: ok` summaries. |
| `stage-artifacts [--env FILE] [--role ROLE]` | Verifies exported bundle archives, copies the archive pair into the target container with a Docker simulation-only `docker cp` waiver, extracts to `/var/lib/loopforge/staging/gerrit`, `/var/lib/loopforge/staging/jenkins`, or `/var/lib/loopforge/staging/jenkins-agent`, and checks manifests/checksums before mutation. Success prints compact `stage-artifacts[role]: ok` summaries. |
| `configure-role [--env FILE] [--role ROLE]` | Runs one role-local configuration phase, or all Docker roles when `--role` is omitted, against the target container and records evidence. Success prints `configure-role[role]: ok`; failures include `log=` and `evidence=`. |
| `validate-role [--env FILE] [--role ROLE]` | Runs one role-local validation phase, or all Docker roles when `--role` is omitted, against the target container and records evidence. Success prints `validate-role[role]: ok`; failures include `log=` and `evidence=`. |
| `configure-integration [--env FILE]` | Configures shared integration state for Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, shared storage, and the Gerrit Trigger server. Success prints a short `configure-integration: ok` summary. |
| `validate-integration [--env FILE]` | Runs passive cross-role readiness validation and writes a marker for later verification. Success prints a short `validate-integration: ok` summary. |
| `prove-integration [--env FILE]` | Requires a matching successful validate marker for the same run, then runs the active cross-role proof. It does not run `validate-integration` implicitly. Success prints a short `prove-integration: ok` summary. |
| `audit-state [--env FILE]` | Performs the explicit Docker container and bind-mount sweep for the selected run. It is read-only and does not rerun other phases. |
| `down [--env FILE]` | Stops harness containers while retaining generated state, logs, artifacts, and evidence. Success prints `down: stopped harness containers`. |
| `clean [--env FILE]` | Stops harness containers with orphan removal and deletes only mutable generated runtime data from the selected run. It preserves exported artifacts, evidence, and logs. |

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

During `init-run`, the selected harness, role, and integration env files
are copied to
`generated/simulation/docker/<run-id>/host/runtime-inputs/` with
mode `0600`. `init-run` also writes a run marker under
`generated/simulation/docker/<run-id>/`. Later lifecycle and cleanup commands
load the private runtime config and verify that marker before operating.

`harness.env` is the redacted public record for inspection. The private
`harness.runtime.env` retains lifecycle values and points at the runtime input
copies.

For v1, Docker simulation does not support arbitrary generated/output roots.
All lifecycle and cleanup commands use the repo-local
`generated/simulation/docker/<run-id>/` tree.

## Simulation Accounts

The shared simulation account contract is defined in `simulation/README.md`.
The Docker target image realizes that contract with product runtime accounts
and native homes: `gerrit` owns `/srv/gerrit`, `jenkins` owns
`/var/lib/jenkins`, and `jenkins-agent` owns `/var/lib/jenkins-agent`.

The image realizes the account model's example numeric IDs: `ci-operator` uses
UID/GID `61000`, `gerrit` uses `61010`, `jenkins` uses `61020`, and
`jenkins-agent` uses `61030`. These IDs are Docker simulation defaults, not
host account mappings.

Docker realizes Jenkins shared storage by bind-mounting one run-local
`target/shared-jenkins-storage` directory into both the Jenkins controller and
Jenkins agent containers at `JENKINS_SHARED_STORAGE_PATH`, normally
`/mnt/jenkins-shared`. `configure-integration` applies the shared
`jenkins-share` group, setgid group-writable permissions, and read/write proof
inside those containers.

The Docker target image also includes the default example target-local
`ci-operator` account. This target-local `ci-operator` OS account has
passwordless sudo for simulation orchestration and privileged helper
operations. The harness may use container-internal delegated privilege for
protected OS operations, but root is not a Loopforge account, helper execution
identity, runtime identity, or supported login identity. The local host account
that invokes `simulate.sh` may have any site-local name and is not renamed,
mapped, or required to be `ci-operator`.

Use `simulate.sh status --env FILE` after `up` to inspect the selected
running simulation. The status command prints the run ID, Compose project,
live browser URLs, and seeded Docker simulation human login accounts. The
Jenkins Gerrit integration account is created later as a Gerrit service
account by the shared integration step, not seeded as an LDAP password user.
It is read-only and fails when the selected run's containers are not running,
so it does not rely on stale port data from rendered config files.

Use `simulate.sh ssh --role ROLE` after `up` to log into a target OS
environment as the target-local `ci-operator` through SSH from the host. The
command uses the rendered
`INTEGRATION_*_TARGET_SSH_*` values and the run-scoped target SSH key and
known-hosts file:

```bash
simulation/docker/simulate.sh ssh --role gerrit
simulation/docker/simulate.sh ssh --role jenkins-controller
simulation/docker/simulate.sh ssh --role jenkins-agent
```

This command intentionally uses the target OS control-plane SSH interface. It
does not use Docker exec and it is separate from Gerrit's service SSH on port
`29418`.

## Output Locations

Docker-generated runtime output is not committed. Docker v1 uses one
repo-local generated run root:

```text
generated/simulation/docker/<run-id>/
```

| Output kind | Docker run-scoped pattern |
| --- | --- |
| Host-contributed inputs | `generated/simulation/docker/<run-id>/host/` |
| Product runtime homes | `generated/simulation/docker/<run-id>/target/product-homes/` |
| Transfer scratch | `generated/simulation/docker/<run-id>/target/artifacts/staging/` |
| Exported artifacts | `generated/simulation/docker/<run-id>/target/artifacts/exported/<bundle>.tar.gz` |
| Harness evidence | `generated/simulation/docker/<run-id>/host/evidence/harness/` |
| Harness bounded logs | `generated/simulation/docker/<run-id>/host/logs/harness/` |
| Integration evidence and logs | `generated/simulation/docker/<run-id>/host/evidence/integration/`, `host/logs/integration/` |
| Target role evidence | `generated/simulation/docker/<run-id>/target/evidence/<role>/` |
| Target role bounded logs | `generated/simulation/docker/<run-id>/target/logs/<role>/` |

Implementation-specific harness state can live below child directories inside
those roots, but the operator-facing Docker model has one run-scoped output
layout. Shared simulation contracts for input custody, helper-visible paths,
artifact staging, LDAP secret handling, retained outputs, and integration key
custody live in `simulation/README.md`, `docs/artifact-bundle-contract.md`,
and `docs/directory-model.md`.

Docker realizes those contracts with container lifecycle, generated bind-mount
sources, and explicitly labeled Docker `cp` waivers:

- Role helper roots `/var/lib/loopforge` and `/var/log/loopforge` are not
  Docker bind mounts in role containers.
- `prepare-artifacts` exports bundle archive pairs from the bundle factory to
  `target/artifacts/exported/` through the harness collector.
- `stage-artifacts` copies archive pairs into target containers with a Docker
  simulation-only `docker cp` waiver, then extracts and verifies them under
  `/var/lib/loopforge/staging`.
- Full reviewed helper env files remain under `host/runtime-inputs/`; Docker
  copies them to `/home/ci-operator/loopforge-inputs` with a labeled Docker
  `cp` input waiver before helper execution.
- The run-scoped target SSH public key is staged as Docker control-plane input
  and installed as the target-local `ci-operator` `authorized_keys` file during
  `up`; the private key remains only under `host/target-ssh/`.
- The host collector copies bounded evidence and logs from containers with a
  labeled Docker `cp` collector waiver.

## Cleanup Contract

`down` and `clean` are deliberately separate. `down` maps to Docker Compose
teardown and retains generated output for review. Docker bind mounts can leave
host files owned by container users, and Compose does not delete those
bind-mounted directories, so `clean` is the explicit housekeeping command.

`clean` follows the shared retained-output contract from
`docs/directory-model.md`. It verifies the selected run marker and operates
only under the canonical repo-local generated run root. It backs up retained
outputs, clears active retained output directories for later run reuse, and
removes Docker mutable generated runtime data: host rendered inputs and target
SSH material, `target/helper-state/`, `target/product-homes/`,
`target/artifacts/staging/`, `target/ldap/`, and
`target/shared-jenkins-storage/`. `target/helper-state/` is retained only for
host-orchestrated integration helper state, not role helper roots. If the host
user cannot remove container-owned files, `clean` may use a one-shot cleanup
container mounted only to the validated run root.

See `docs/lifecycle-contract.md` for phase behavior rules and
`docs/directory-model.md` for generated path ownership, host/target dominance,
and retained-output backup ownership.

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
- Helper env files under `host/runtime-inputs/helper-envs/` exist for phases
  that need them.
- Expected generated bind source directories exist before container lifecycle
  phases use them.

When selected containers already exist, resume/rerun phases also validate that
container bind mounts still point at the selected canonical run root. A host
probe written to each required bind source must be visible at the expected
container destination before a phase relies on that mount.

If generated state or bind-mount liveness is inconsistent, lifecycle phases
fail clearly instead of recreating state or rerunning earlier phases. Recover
with `down` or `clean`.

| Situation | Expected behavior |
| --- | --- |
| No selected containers and no generated run state | `init-run` may create the selected generated run state. `up` requires rendered runtime config first. |
| Selected containers exist and generated bind mounts match the selected run | Resume/rerun phases may continue after validating their own prerequisites. Use `audit-state` for explicit bind-mount inspection. |
| Selected containers exist but `generated/` was removed or recreated | Resume/rerun phases fail because existing containers are bound to missing or stale host paths. Use `down` or `clean` before starting again. |
| No selected containers exist but a previous generated folder remains | `init-run` may create or overwrite generated runtime config for the selected run. Later phases use the newly rendered state. |
| Partial or inconsistent generated state exists | Lifecycle phases fail clearly. If containers exist, use `down` or `clean`; if no containers exist, rerun `init-run`. |

`down` stops and removes selected simulation containers while retaining
generated output for review. It supports bootstrap-only recovery when runtime
config is missing or inconsistent because stale containers may be the problem
being recovered from.

`clean` may share the same container cleanup recovery as `down`. It must not
delete generated files outside the canonical run root. If runtime config is
missing or inconsistent but the canonical run root still exists, `clean` may
remove selected containers, remove known mutable generated paths, back up
retained outputs, and clear active retained output directories. If the
canonical run root is missing, it reports that host generated cleanup was
skipped.

`audit-state` is the explicit read-only command for the expensive container
and bind-mount sweep. It checks live selected containers against the selected
run root for operator inspection and is not part of the default path for
normal lifecycle phases.

Typical flows:

```bash
simulation/docker/simulate.sh --env FILE init-run
simulation/docker/simulate.sh --env FILE up
simulation/docker/simulate.sh --env FILE configure-role
simulation/docker/simulate.sh --env FILE validate-role
simulation/docker/simulate.sh --env FILE configure-integration
simulation/docker/simulate.sh --env FILE validate-integration
simulation/docker/simulate.sh --env FILE prove-integration
simulation/docker/simulate.sh --env FILE down
simulation/docker/simulate.sh --env FILE clean
```

Use `configure-role` and `validate-role` for role-local work only. Use
`validate-integration` for passive cross-role readiness and
`prove-integration` only after `validate-integration` has already passed for
the same initialized run.
Use `audit-state` when you need the slower bind-mount audit for an existing
run. Normal lifecycle phases keep the cheap runtime-config check only.

## Integration Boundary

The shared integration boundary is defined in `simulation/README.md` and
`docs/lifecycle-contract.md`. Docker orchestrates that shared helper through
the Docker target SSH inventory and generated Docker run state.

`validate-integration` and `prove-integration` must fail or report blocked
rather than claim Docker readiness when real integration proof is unavailable.
Forbidden synthetic success markers in role or integration logs are treated as
failures.

Source-boundary rules, including simulation-only public internet fallback for
target-host Ubuntu/OS dependency installation, are shared in
`simulation/README.md`.
