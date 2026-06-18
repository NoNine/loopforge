# Simulation Model

This directory defines the simulation model for the v1 Gerrit/Jenkins setup
package.

The model has two layers:

1. Docker-based simulation first.
2. VM-based simulation second.

Both layers use the same five-machine topology:

| Machine/environment | Docker form | VM form | Responsibility |
| --- | --- | --- | --- |
| Bundle factory | Container | VM | Runs role helper `prepare-artifacts` commands and produces curated application artifacts, plugins, manifests, and checksums. |
| LDAP | Container | VM | Hosts LDAP bind, admin, and test accounts and groups. |
| Gerrit | Container | VM | Runs Gerrit with LDAP authentication, SSH access, integration permissions, and the `Verified` label. |
| Jenkins controller | Container | VM | Runs Jenkins, LDAP/JCasC configuration, Gerrit Trigger, and agent registration. |
| Jenkins agent | Container | VM | Runs SSH build jobs scheduled by Jenkins. |

The simulation model derives account usage from `docs/account-model.md`. It
does not introduce a separate account taxonomy. The `operator` account is a
local OS account on simulation machines only; it is not a Gerrit or Jenkins
product account.

Version baseline inputs for both simulation layers:

- Ubuntu 24.04.4 LTS, release `24.04`, codename `noble`
- OpenJDK 21 for Gerrit, Jenkins controller, and Jenkins agent
- Gerrit `3.13.6`
- Jenkins controller `2.555.3 LTS`
- Jenkins Plugin Installation Manager Tool `2.15.0`
- Jenkins agent OpenJDK 21 plus SSH server/client tooling and the Jenkins SSH
  Build Agents plugin from the controller plugin bundle

Ubuntu/OS dependencies and application artifacts are separate supply lanes.
Target hosts may use approved internal Ubuntu/OS package repositories for OS
dependencies. Application artifacts are prepared only in the bundle factory,
then staged to Gerrit, Jenkins controller, and Jenkins agent target/service
environments and verified by manifest and checksum before mutation.

Public internet fallback for target-host Ubuntu/OS dependency installation is
simulation-only and must be labeled `simulation-only` in docs, logs, and
verification summaries. Target hosts must not download Gerrit/Jenkins
application artifacts from the public internet as fallback. In v1, offline Ubuntu
dependency bundle workflows are not supported.

Generated runtime output is not committed. Future Docker and VM steps should
write generated state, staged artifacts, evidence, and bounded logs under
layer- and run-scoped paths so separate runs do not collide.

Use these canonical roots and subpath patterns:

| Output kind | Canonical root | Run-scoped pattern |
| --- | --- | --- |
| State | `simulation/state/` | `simulation/state/<layer>/<run-id>/` |
| Staged artifacts | `simulation/staging/` | `simulation/staging/<layer>/<run-id>/<environment>/` |
| Evidence | `simulation/evidence/` | `simulation/evidence/<layer>/<run-id>/` |
| Bounded logs | `logs/` | `logs/<layer>/<run-id>/` |

`<layer>` is `docker` or `vm`. `<run-id>` is a unique run identifier, such as
a UTC timestamp plus a short label. `<environment>` is one of
`bundle-factory`, `ldap`, `gerrit`, `jenkins-controller`, or
`jenkins-agent`.

These paths are generated runtime output unless a file in the tree states
otherwise. Keep them ignored or documented as generated when created by future
simulation steps.

The scripts named below are planned future command surfaces, not commands
implemented in Step 3. Checkpoint ownership is split by layer:

| Checkpoint | Planned Docker owner | Planned VM owner |
| --- | --- | --- |
| Preflight | `simulation/docker/docker-harness.sh preflight` for role-gate harness readiness; `simulation/docker/docker-verify.sh preflight` for full Docker simulation readiness. | `simulation/vm/vm-verify.sh check --preflight-only` or `simulation/vm/vm-verify.sh full --preflight-only`. |
| Input rendering | `simulation/docker/docker-harness.sh render-config` for role gates; `simulation/docker/docker-verify.sh render-config` for full Docker simulation. | `simulation/vm/vm-verify.sh bootstrap`. |
| Artifact preparation | `simulation/docker/docker-harness.sh prepare-artifacts --role ...` for role gates; `simulation/docker/docker-verify.sh prepare-artifacts` for full Docker simulation aggregation. | `simulation/vm/vm-verify.sh prepare-artifacts`. |
| Artifact staging | `simulation/docker/docker-harness.sh stage-artifacts --role ...` for role gates; `simulation/docker/docker-verify.sh stage-artifacts` for full Docker simulation aggregation. | `simulation/vm/vm-verify.sh stage-artifacts`. |
| Service configuration | `simulation/docker/docker-harness.sh up` for role-gate containers; `simulation/docker/docker-verify.sh up` for full Docker simulation. | `simulation/vm/vm-verify.sh configure`. |
| Readiness checks | `simulation/docker/docker-harness.sh run-role-gate --role ...` for role readiness; `simulation/docker/docker-verify.sh check` plus `scripts/integration-setup.sh validate-integration` for full Docker readiness. | `simulation/vm/vm-verify.sh check` plus the shared integration helper when VM support exists. |
| End-to-end execution | `simulation/docker/docker-verify.sh full-verify` orchestrating `scripts/integration-setup.sh verify-trigger`. | `simulation/vm/vm-verify.sh execute` or `simulation/vm/vm-verify.sh full` orchestrating the shared integration helper. |
| Evidence audit | Role-local `collect-evidence`, integration-local `scripts/integration-setup.sh collect-evidence`, Docker harness evidence, `docker-verify.sh` summaries, and later global aggregation. | `simulation/vm/vm-verify.sh audit`, integration-local evidence, and later global aggregation. |

The Docker layer is the first end-to-end integration gate for Gerrit Trigger
behavior, Jenkins agent scheduling, and `Verified` voting. The VM layer repeats
the Docker-proven flow in a systemd-oriented, production-like environment
after Docker behavior is stable.

Role helpers stay role-local in both layers. Cross-role SSH, trigger setup,
integration validation, trigger verification, and integration evidence use
`scripts/integration-setup.sh`. Current scaffold-level integration commands
must fail closed until the later real Docker or VM implementation exists.
