# Docker Simulation

Docker simulation is the first executable simulation layer for the v1
Gerrit/Jenkins setup package. The single Docker entrypoint is:

```bash
simulation/docker/docker-harness.sh <command>
simulation/docker/docker-harness.sh [--env FILE] <command>
```

`docker-harness.sh` owns role-local gates and cross-role integration
orchestration. Do not add standalone Docker phase scripts or a second Docker
verifier CLI.

## Command Reference

| Command | Purpose |
| --- | --- |
| `preflight [--env FILE]` | Validates required tools, Compose availability, static harness files, baseline labels, and script wiring. Terminal output is a short `preflight: ok ...` summary; details stay in generated evidence. |
| `render-config [--env FILE]` | Loads the bootstrap env file, copies the harness, role, and integration env inputs into private run-scoped runtime inputs, resolves browser ports, writes rendered/runtime env files, and writes the artifact manifest contract. Terminal output is a short `render-config: ok run-id=...` summary. |
| `up` | Starts the bundle factory, LDAP, Gerrit target, Jenkins controller target, and Jenkins agent target containers. Success prints one short `up: started ...` summary. |
| `status [--env FILE]` | Requires the selected run's containers to be running, inspects live published browser ports, and prints run identity, browser URLs, and Docker simulation login accounts. |
| `prepare-artifacts [--env FILE] [--role ROLE]` | Runs one role, or all Docker roles when `--role` is omitted, inside the bundle factory and validates manifests/checksums. Success prints compact `prepare-artifacts[role]: ok` summaries. |
| `stage-artifacts [--env FILE] [--role ROLE]` | Stages one role, or all Docker roles when `--role` is omitted, to target containers and verifies manifests/checksums before mutation. Success prints compact `stage-artifacts[role]: ok` summaries. |
| `run-role-gate [--env FILE] --role ROLE` | Runs one role-local readiness gate against its target container and records evidence. Success prints `run-role-gate[role]: ok`; failures include `log=` and `evidence=`. |
| `check [--env FILE]` | Runs all role gates, then calls `scripts/integration-setup.sh` for Gerrit/Jenkins/agent integration readiness. Success prints a short `check: integration ok` summary. |
| `full-verify [--env FILE]` | Runs `check`; when readiness passes, calls `scripts/integration-setup.sh verify-trigger`. Success prints a short `full-verify: integration ok` summary. |
| `down [--env FILE]` | Stops harness containers while retaining generated state, logs, artifacts, and evidence. Success prints `down: stopped harness containers`. |

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

During `render-config`, the selected harness, role, and integration env files
are copied to `simulation/state/docker/<run-id>/rendered/runtime-inputs/` with
mode `0600`. Later lifecycle commands load the private runtime config and use
those run-scoped copies, but they still bootstrap from the same env file so
they can resolve the correct run directory without shell exports.

`harness.env` is the redacted public record for inspection. The private
`harness.runtime.env` retains lifecycle values and points at the runtime input
copies.

## Simulation Accounts

The Docker target image includes product runtime accounts with native homes:
`gerrit` owns `/srv/gerrit`, `jenkins` owns `/var/lib/jenkins`, and
`jenkins-agent` owns `/var/lib/jenkins-agent`. These are separate from
application admin, integration, LDAP bind, and test accounts.

The Docker target image also includes a local `ci-operator` OS account with
passwordless sudo for simulation orchestration and privileged helper
operations. The `ci-operator` account does not own `/srv/gerrit`,
`/var/lib/jenkins`, or `/var/lib/jenkins-agent` and is not a Gerrit, Jenkins
controller, or Jenkins agent runtime account. Root remains available for
privileged container operations where the harness needs it.

Use `docker-harness.sh status --env FILE` after `up` to inspect the selected
running simulation. The status command prints the run ID, Compose project,
live browser URLs, and seeded Docker simulation login accounts. It is
read-only and fails when the selected run's containers are not running, so it
does not rely on stale port data from rendered config files.

## Output Locations

Docker-generated runtime output is not committed.

| Output kind | Docker run-scoped pattern |
| --- | --- |
| State | `simulation/state/docker/<run-id>/` |
| Staged artifacts | `simulation/staging/docker/<run-id>/<environment>/` |
| Evidence | `simulation/evidence/docker/<run-id>/` |
| Bounded logs | `logs/docker/<run-id>/` |

Implementation-specific harness state can live below child directories inside
those roots, but the operator-facing Docker model has one run-scoped output
layout.

`/harness/state` is a harness sideband mount for reviewed inputs,
coordination state, generated control scripts, fingerprints, status, and
evidence references. It does not replace normal target runtime locations.
Target operations still install or update product-owned paths such as
`/srv/gerrit`, `/var/lib/jenkins`, `/var/lib/jenkins-agent`,
`$JENKINS_HOME/.ssh/known_hosts`, and agent `authorized_keys`.

Transient target-local files under `/tmp` are acceptable when they stage
payloads for normal target APIs or runtime installation, for example Gerrit
REST JSON bodies, public-key handoff, or installing Jenkins `known_hosts`.
They must not be used to bypass expected access to a sideband file under
`/harness/state`.

Harness sideband directories are host-owned and grant container runtime
access by group and mode. Jenkins-owned private keys under integration keys
are the deliberate exception: the Jenkins controller owns the
Jenkins-to-Gerrit and Jenkins-to-agent private keys, while generated Groovy
scripts, status files, evidence, and public-key metadata remain harness
sideband state.

## Integration Boundary

Role helpers stay role-local. Cross-role SSH, Gerrit Trigger setup,
integration validation, trigger verification, and integration evidence use
`scripts/integration-setup.sh`.

`check` and `full-verify` must fail or report blocked rather than claim Docker
readiness when real integration proof is unavailable. Forbidden synthetic
success markers in role or integration logs are treated as failures.

Public internet fallback on target hosts is simulation-only and applies only
to Ubuntu/OS dependency installation. It is not support for target-host
application artifact downloads, and v1 is not a strict air-gapped installer.
