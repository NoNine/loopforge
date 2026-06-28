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

Generated-state and stale-container behavior is defined in
`docs/docker-simulation-state-lifecycle.md`.

The shared Docker target image is a simulation superset. It combines
role-runtime packages, helper-script packages, and Docker harness packages; it
is not authority for native target-host baselines. See
`docs/package-requirements.md` for the package classification.

## Command Reference

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
| `stage-artifacts [--env FILE] [--role ROLE]` | Verifies exported bundle archives, copies the archive pair into the target container with a Docker simulation-only `docker cp` waiver, extracts to `/var/lib/loopforge/staging/gerrit-artifacts-bundle`, `/var/lib/loopforge/staging/jenkins-artifacts-bundle`, or `/var/lib/loopforge/staging/jenkins-agent-artifacts-bundle`, and checks manifests/checksums before mutation. Success prints compact `stage-artifacts[role]: ok` summaries. |
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

The Docker target image includes product runtime accounts with native homes:
`gerrit` owns `/srv/gerrit`, `jenkins` owns `/var/lib/jenkins`, and
`jenkins-agent` owns `/var/lib/jenkins-agent`. These are separate from
application admin, integration, LDAP bind, and test accounts.
The image realizes the account model's example numeric IDs: `ci-operator`
uses UID/GID `61000`, `gerrit` uses `61010`, `jenkins` uses `61020`, and
`jenkins-agent` uses `61030`. These IDs are Docker simulation defaults, not
host account mappings.

The Docker target image also includes the default example target-local
`ci-operator` account. This target-local `ci-operator` OS account has
passwordless sudo for simulation orchestration and privileged helper
operations. The operator account does not own `/srv/gerrit`,
`/var/lib/jenkins`, or `/var/lib/jenkins-agent` and is not a Gerrit, Jenkins
controller, or Jenkins agent runtime account. The harness may use
container-internal delegated privilege for protected OS operations, but root
is not a Loopforge account, helper execution identity, runtime identity, or
supported login identity.
The local host account that invokes `simulate.sh` may have any site-local name
and is not renamed, mapped, or required to be `ci-operator`.

Use `simulate.sh status --env FILE` after `up` to inspect the selected
running simulation. The status command prints the run ID, Compose project,
live browser URLs, and seeded Docker simulation login accounts. It is
read-only and fails when the selected run's containers are not running, so it
does not rely on stale port data from rendered config files.

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
| Target helper state | `generated/simulation/docker/<run-id>/target/helper-state/` |
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
layout.

The Docker harness does the simulation work it must do: create generated run
directories, provide bind-mount sources, stage rendered inputs, orchestrate
containers, and perform explicitly labeled Docker `cp` waivers. Role helpers
still perform the lifecycle work inside helper-visible paths, including
artifact preparation, target-local mutation, validation, and evidence
collection.

LDAP bind passwords are not written to harness secret files, rendered helper
env files, runtime env files, or artifact bundles. Docker simulation injects
the LDAP bind password only into helper command environments for the commands
that need LDAP proof or product runtime configuration. Product runtime config
files may still persist product-required LDAP settings after the relevant role
helper writes them.

`prepare-artifacts` writes role artifacts and packs the archive pair inside the
bundle-factory preparing root, then the harness collector exports those files to
`target/artifacts/exported/<bundle>.tar.gz` plus `.sha256`.
`stage-artifacts` consumes those archives through an explicit Docker
simulation-only `docker cp` waiver, then extracts and verifies them inside the
target container under `/var/lib/loopforge/staging` before helper validation.
Docker target containers do not bind-mount host staging directories onto the
helper-visible bundle paths.

Bundle-factory and target helper state are helper-visible at
`/var/lib/loopforge`, and helper logs are helper-visible at
`/var/log/loopforge`. Bundle-factory `/var/lib/loopforge` debug subdirectories
are host-backed under `host/bundle-factory/` for rendered inputs and
`target/helper-state/bundle-factory/` for bundle-factory-produced outputs,
not `target/product-homes/`.
Successful artifacts still leave that environment through the explicit export
step. Rendered helper env files are operator-reviewed runtime inputs first,
then copied into helper paths before helper execution. The host-side generated
directories are for operator review, debugging, evidence collection, and
cleanup; they are not a target payload transfer mechanism.

Active target role evidence and log directories are target-dominated
helper-owned output, not host sideband state. The Docker harness prepares
the bind-mounted backing directories for the target-local
`ci-operator:ci-operator` identity so Docker mounts are writable, while role
helpers own role-local lifecycle creation, cleanup, validation, and evidence
writes under `/var/lib/loopforge` and `/var/log/loopforge`. Host-owned copies
exist only under `host/`, such as clean backup snapshots.

Target operations still install or update product-owned paths such as
`/srv/gerrit`, `/var/lib/jenkins`, `/var/lib/jenkins-agent`,
`$JENKINS_HOME/.ssh/known_hosts`, and agent `authorized_keys`.

Transient target-local files under `/tmp` are acceptable when they stage
payloads for normal target APIs or runtime installation, for example Gerrit
REST JSON bodies, public-key handoff, or installing Jenkins `known_hosts`.
They must not be used to bypass expected access to reviewed helper inputs or
helper-owned state.

Helper-owned sideband directories may be backed by host directories in the
Docker simulation, but the container helper owns the runtime files. The host
collector may read generated evidence, logs, and exported artifacts and may
clean up the selected run root. Jenkins-owned private keys under integration
keys are the deliberate exception: the Jenkins controller owns the
Jenkins-to-Gerrit and Jenkins-to-agent private keys, while generated Groovy
scripts, status files, evidence, and public-key metadata remain harness
sideband state.

## Cleanup Contract

`down` and `clean` are deliberately separate. `down` maps to Docker Compose
teardown and retains generated output for review. Docker bind mounts can leave
host files owned by container users, and Compose does not delete those
bind-mounted directories, so `clean` is the explicit housekeeping command.

`clean` verifies the selected run marker and operates only under the canonical
repo-local generated run root. It backs up retained outputs from
`target/artifacts/exported/`, `host/evidence/`, `host/logs/`,
`target/evidence/`, and `target/logs/` to
`host/retained-output-backups/<timestamp>/`, then clears the active retained
output directories for later run reuse. Backup snapshots are host-owned
review artifacts; active target outputs are not converted to host ownership in
place. It removes mutable generated runtime data: host rendered inputs and
target SSH material, `target/helper-state/`,
`target/product-homes/`, `target/artifacts/staging/`, `target/ldap/`, and
`target/shared-jenkins-storage/`. If the host user cannot remove
container-owned files, `clean` may use a one-shot cleanup container mounted
only to the validated run root.

See `docs/docker-simulation-state-lifecycle.md` for the detailed fresh-run,
resume/rerun, stale-container, `down`, and `clean` state rules.

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

Role helpers stay role-local. Cross-role SSH, Gerrit Trigger setup,
integration validation, trigger verification, and integration evidence use
`scripts/integration-setup.sh`.

`validate-integration` and `prove-integration` must fail or report blocked
rather than claim Docker readiness when real integration proof is unavailable.
Forbidden synthetic success markers in role or integration logs are treated as
failures.

Public internet fallback on target hosts is simulation-only and applies only
to Ubuntu/OS dependency installation. It is not a fallback for target-host
application artifact downloads, and v1 is not a strict air-gapped installer.
