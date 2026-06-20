# Docker Simulation

Docker simulation is the first executable simulation layer for the v1
Gerrit/Jenkins setup package. The single Docker entrypoint is:

```bash
simulation/docker/docker-harness.sh <command>
simulation/docker/docker-harness.sh render-config [--env FILE]
```

`docker-harness.sh` owns role-local gates and cross-role integration
orchestration. Do not add standalone Docker phase scripts or a second Docker
verifier CLI.

## Command Reference

| Command | Purpose |
| --- | --- |
| `preflight` | Validates required tools, Compose availability, static harness files, baseline labels, and script wiring. It does not read operator env files, render config, or copy runtime inputs. |
| `render-config [--env FILE]` | Loads the selected harness env file, copies the harness, role, and integration env inputs into private run-scoped runtime inputs, resolves browser ports, writes rendered/runtime env files, and writes the artifact manifest contract. |
| `up` | Starts the bundle factory, LDAP, Gerrit target, Jenkins controller target, and Jenkins agent target containers. |
| `prepare-artifacts [--role ROLE]` | Runs one role, or all Docker roles when `--role` is omitted, inside the bundle factory and validates manifests/checksums. |
| `stage-artifacts [--role ROLE]` | Stages one role, or all Docker roles when `--role` is omitted, to target containers and verifies manifests/checksums before mutation. |
| `run-role-gate --role ROLE` | Runs one role-local readiness gate against its target container and records evidence. |
| `check` | Runs all role gates, then calls `scripts/integration-setup.sh` for Gerrit/Jenkins/agent integration readiness. |
| `full-verify` | Runs `check`; when readiness passes, calls `scripts/integration-setup.sh verify-trigger`. |
| `down` | Stops harness containers while retaining generated state, logs, artifacts, and evidence. |

`ROLE` is one of `gerrit`, `jenkins-controller`, or `jenkins-agent`.

## Input Model

If `--env FILE` is omitted, `render-config` uses
`simulation/docker/examples/docker.env.example`. Copy that file
outside committed examples before using real operator values.

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
those run-scoped copies, so they do not depend on the original operator env
files remaining unchanged.

`harness.env` is the redacted public record for inspection. The private
`harness.runtime.env` retains lifecycle values and points at the runtime input
copies.

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
