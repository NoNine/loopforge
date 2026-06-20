# Docker Simulation

Docker simulation is the first planned executable simulation layer for the v1
Gerrit/Jenkins setup package.

It uses the five-machine model from `simulation/README.md`, with the bundle
factory represented as a container. The bundle factory container runs role
helper `prepare-artifacts` commands and produces curated application
artifacts, plugins, manifests, and checksums before any service container
starts.

The bundle factory is an environment, not a public API. Do not add a
`bundle-factory-helper.sh`; artifact preparation remains exposed through the
role helpers' `prepare-artifacts` commands.

Docker is planned as the shared role-gate harness and the first full
integration verification gate. Role-step readiness gates will run against the
shared Docker harness before the full Docker verifier takes over the
end-to-end path.

## Role And Command Model

The scripts named here are planned future command surfaces, not files
implemented by Step 3. Every command surface uses one owning script plus a
subcommand.

- Role helpers use `scripts/<role>-setup.sh <command>`.
- Cross-role integration uses `scripts/integration-setup.sh <command>`.
- Docker role gates use `simulation/docker/docker-harness.sh <command>`.
- Full Docker simulation uses `simulation/docker/docker-verify.sh <command>`.

Do not add standalone role phase scripts such as `scripts/preflight.sh` or
Docker phase scripts such as `simulation/docker/check.sh`.

Checkpoint ownership for Docker is:

| Checkpoint | Planned Docker owner |
| --- | --- |
| Preflight | `simulation/docker/docker-harness.sh preflight` for role-gate harness readiness; `simulation/docker/docker-verify.sh preflight` for full Docker simulation readiness. |
| Input rendering | `simulation/docker/docker-harness.sh render-config` for role gates; `simulation/docker/docker-verify.sh render-config` for full Docker simulation. |
| Artifact preparation | `simulation/docker/docker-harness.sh prepare-artifacts --role ...` for role gates; `simulation/docker/docker-verify.sh prepare-artifacts` for full Docker simulation aggregation. |
| Artifact staging | `simulation/docker/docker-harness.sh stage-artifacts --role ...` for role gates; `simulation/docker/docker-verify.sh stage-artifacts` for full Docker simulation aggregation. |
| Service configuration | `simulation/docker/docker-harness.sh up` for role-gate containers; `simulation/docker/docker-verify.sh up` for full Docker simulation. |
| Readiness checks | `simulation/docker/docker-harness.sh run-role-gate --role ...` for role readiness; `simulation/docker/docker-verify.sh check` plus `scripts/integration-setup.sh validate-integration` for full Docker readiness. |
| End-to-end execution | `simulation/docker/docker-verify.sh full-verify` orchestrating `scripts/integration-setup.sh verify-trigger`. |
| Evidence audit | Role-local `collect-evidence`, integration-local `scripts/integration-setup.sh collect-evidence`, Docker harness evidence, and `docker-verify.sh` summaries. |

## Model Requirements

The Docker simulation must include:

- Bundle factory container
- LDAP container
- Gerrit container
- Jenkins controller container
- Jenkins agent container

The Docker model derives account usage from `docs/account-model.md`. It must
exercise the Gerrit admin account, Jenkins admin account, Jenkins Gerrit
integration account, test user account, LDAP bind account, Gerrit runtime
account, Jenkins runtime account, Jenkins agent runtime account, and the
`operator` account. The `operator` account remains a local OS simulation
account, not a Gerrit or Jenkins product account.

## Source Boundaries

Ubuntu/OS dependencies and application artifacts stay on separate lanes.
Target hosts may use approved internal Ubuntu/OS package repositories for OS
dependencies. Application artifacts are prepared only in the bundle factory,
staged to the target containers, and verified by manifest and checksum before
mutation.

Public internet fallback for target-host Ubuntu/OS dependency installation is
simulation-only and must be labeled `simulation-only` in docs, logs, and
verification summaries. Target hosts must not download Gerrit/Jenkins
application artifacts from the public internet as fallback. In v1, offline Ubuntu
dependency bundle workflows are not supported.

## Local Browser Access

The Docker harness publishes service HTTP ports on loopback for local manual
simulation checks. Ports are selected per run from currently available
`127.0.0.1` ports unless the operator explicitly sets
`HARNESS_GERRIT_HTTP_HOST_PORT` or `HARNESS_JENKINS_HTTP_HOST_PORT` to an
available numeric TCP port before `render-config`, `preflight`, or `up`.

The selected values are persisted in the harness rendered env for the same
`HARNESS_RUN_ID`:

```bash
simulation/docker/docker-harness.sh render-config
rg 'HARNESS_.*HTTP_HOST_PORT|HARNESS_.*BROWSER_URL' \
  simulation/state/docker/harness/<run-id>/rendered/harness.env
```

The command output also prints the browser URLs:

- Gerrit: `http://127.0.0.1:<chosen-port>/`
- Jenkins: `http://127.0.0.1:<chosen-port>/login`

These browser-visible URLs are for manual simulation inspection on the local
operator workstation only. They are not production exposure guidance and must
not be treated as a recommended network binding for production-like Gerrit or
Jenkins hosts.

## Output Locations

Docker-generated runtime output is not committed. The shared output convention
is canonical in `simulation/README.md`.

| Output kind | Docker run-scoped pattern |
| --- | --- |
| State | `simulation/state/docker/<run-id>/` |
| Staged artifacts | `simulation/staging/docker/<run-id>/<environment>/` |
| Evidence | `simulation/evidence/docker/<run-id>/` |
| Bounded logs | `logs/docker/<run-id>/` |

`<environment>` is one of `bundle-factory`, `ldap`, `gerrit`,
`jenkins-controller`, or `jenkins-agent`. These paths are generated runtime
output and should be treated as ignored or generated by future Docker steps.

## Verification Scope

The Docker layer will be responsible for the first real end-to-end Gerrit
Trigger workflow:

- LDAP readiness
- local OS runtime-account readiness
- Gerrit HTTP and SSH readiness
- Jenkins HTTP, LDAP, JCasC, and plugin readiness
- Jenkins-to-Gerrit SSH readiness
- event streaming readiness
- agent readiness
- disposable change, Jenkins trigger, agent job, and `Verified +1`

Disposable Gerrit changes are part of the simulation evidence contract. The
`stream-events` validation changes prove real event streaming. The verification
change proves the Gerrit Trigger event path, Jenkins job mapping, Jenkins agent
execution, and `Verified +1` review posting. These changes may remain open and
show missing submit requirements because cleanup and submission are outside the
current Docker simulation contract.

Docker Step 11 should call role helpers for role-local lifecycle only, then
call `scripts/integration-setup.sh` for Jenkins-to-Gerrit SSH,
Jenkins-to-agent SSH, trigger configuration, integration validation, trigger
verification, and integration evidence. Until that real implementation exists,
the shared integration helper must fail closed rather than claim Docker
integration success.

Future Docker verifiers must fail or report blocked rather than claim
comparable readiness when the Ubuntu, Java, Gerrit, Jenkins controller,
plugin-manager, or Jenkins agent/plugin-bundle versions differ from the
version baseline in `simulation/README.md`.
