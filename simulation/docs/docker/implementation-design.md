# Docker Simulation Harness Implementation Design

This document owns Docker-specific module structure, capability boundaries,
dependency direction, and internal API conventions.
`simulation/docs/shared/simulation-model.md` owns the common public command
contract, while `simulation/docs/docker/docker-simulation.md` owns Docker
syntax and realization deltas. `simulation/docs/shared/harness-design.md` owns
the common harness structure and implemented shared foundation, and
`simulation/docs/shared/lifecycle-state-model.md` owns exact cross-backend state and
command guards. `simulation/docs/shared/run-plan-transition-protocol.md` owns
structured checkpoint-result capture and verification plus run-step commitment.

Docker realizes the shared module roles with Docker-local capability APIs.
Compose, containers, bind data, loopback ports, baseline archives, transport
waivers, and live resource ownership are not shared backend APIs.

## Module Layout

```text
simulation/docker/
  simulate.sh
  lib/
    paths.sh
    config.sh
    state.sh
    compose.sh
    ports.sh
    inputs.sh
    ssh.sh
    docker-set.sh
    baseline.sh
    artifacts.sh
    roles.sh
    integration.sh
    evidence.sh
    lifecycle.sh
```

`simulate.sh` maps the Docker entrypoint onto the shared thin-CLI role and
dispatches only to `docker_cmd_*` lifecycle entrypoints.

`paths.sh` maps the shared path-foundation role onto the Docker set, lock, run,
bind-runtime, and baseline paths defined by
`simulation/docs/shared/generated-state-layout.md`.

`config.sh` owns Docker defaults, env selection, selected identities, stable
loopback endpoint values, and rendered Docker configuration. `inputs.sh` owns
effective Docker input rendering and publication. Neither owns live container
queries or run step progression.

`state.sh` adapts shared run, active-run, and run step mechanics to
Docker generated state. It does not query live Docker resources or define role
and integration postconditions.

`compose.sh` and `ports.sh` own Docker infrastructure primitives: Compose
selection, container identity and runtime queries, mount inspection, and
loopback port allocation. They must not invoke lifecycle commands or role and
integration helpers.

`ssh.sh` owns target OS control-plane access, including target SSH key custody,
known-hosts refresh, authorized-key staging, inventory lookup, and interactive
SSH. Docker-specific transfer waivers remain explicit.

`docker-set.sh` owns selected simulation-set coordination: container and
network ownership, create/start/stop/destroy/status/audit capabilities, and
reusable resource checks. It may combine Docker infrastructure with state but
must not complete role or integration product checkpoints.

`baseline.sh` is the Step 13a M4 boundary for Docker baseline identity,
capture, verification, and restore. It owns checksummed bind archives, numeric
root metadata, image and Compose bindings, public target SSH fingerprints, and
the restricted restore container used only by `restore-baseline`.

`artifacts.sh` owns bundle-factory preparation, exported review copies, Docker
transfer-waiver staging, and target-side manifest and checksum verification.

`roles.sh` owns role-helper invocation and verifies helper-owned configure and
observational-validation results. It must not own the role postcondition,
container lifecycle, or integration setup.

`integration.sh` owns the private invocation adapter and calls to
`scripts/integration-setup.sh` for configuration, validation, and proof. The
integration helper owns those postconditions; this module verifies them for
run-plan commitment.

`evidence.sh` owns Docker evidence collection and capture normalization. It
remains backend-local and does not manufacture checkpoint outcomes.

`lifecycle.sh` maps the shared command-orchestration role onto Docker
capabilities. It remains the only Docker command-shaped implementation layer.

## Dependency Direction

The intended dependency direction is:

```text
simulate -> lifecycle
lifecycle -> docker-set/baseline/inputs/artifacts/roles/integration/ssh/state/config
docker-set/baseline -> compose/ports/state/config/paths
inputs -> artifacts/state/config/paths
artifacts/roles/integration/ssh -> compose/state/config/paths/evidence
compose/ports -> config/paths
state -> config/paths
config -> paths
```

Lower layers must not call `docker_cmd_*` lifecycle entrypoints. `state.sh`
must not query Docker or Compose. Compose and port primitives must not call
target control-plane, role, integration, or lifecycle functions. No Docker
module may source VM harness internals.

## Internal API

Command entrypoints use `docker_cmd_*`. Cross-module capability entrypoints use
a module prefix such as `docker_set_*`, `docker_ssh_*`,
`docker_artifacts_*`, `docker_roles_*`, or `docker_integration_*`. Private
helpers use `__docker_*` when a name is needed outside a small local scope.

Mechanical extraction may temporarily retain established function names while
callers and tests are characterized. Do not retain compatibility wrappers
after all repository callers move to the capability API.

## Refactor And Verification Policy

Structural refactor slices preserve public commands, options, terminal output,
generated paths, markers, evidence, cleanup behavior, and Docker waivers. Use
existing CLI tests as characterization coverage before changing internal APIs.
Run syntax, documentation, layout, terminal-summary, input-lifecycle,
artifact, role, integration, and cleanup tests for each slice. An end-to-end
Docker simulation is not required for behavior-preserving module movement and
remains subject to the execution ledger guardrail.
