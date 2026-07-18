# Docker Simulation Harness Implementation Design

This document owns Docker-specific module structure, capability boundaries,
dependency direction, and internal API conventions. `simulation/docker/README.md`
owns the public Docker command contract. `simulation/docs/harness-design.md`
owns shared harness architecture, and
`simulation/docs/lifecycle-state-model.md` owns exact cross-backend state and
command guards. `simulation/docs/checkpoint-coordination.md` owns the boundary
among helper completion state, evidence, and workflow publication.

Docker and VM simulation share lifecycle meanings, not backend APIs. Docker
modules may follow the VM harness's capability-shaped layering where the
ownership boundary is the same, but Compose, containers, bind data, loopback
ports, baseline archives, and Docker transfer waivers remain Docker-local.

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
    ssh.sh
    docker-set.sh
    baseline.sh
    artifacts.sh
    roles.sh
    integration.sh
    evidence.sh
    lifecycle.sh
```

`simulate.sh` is the public entrypoint. It parses CLI arguments, loads shared
and Docker-local modules, and dispatches only to command-shaped lifecycle
entrypoints.

`paths.sh` owns canonical run-root and set-root paths. Other modules must not
reassemble generated path contracts.

`config.sh` owns defaults, env loading, selected identities, stable endpoint
values, input selection, and rendered configuration. It does not own live
container queries or checkpoint progression.

`state.sh` owns Docker wrappers around shared run markers, active-run and
workflow bindings, generated-state validation, and generic workflow-ledger
publication. It does not query live Docker resources or define role and
integration postconditions.

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
must not complete role or integration checkpoints.

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
workflow publication.

`evidence.sh` owns the Docker evidence schema, Docker collection waivers, and
role evidence normalization. It remains backend-local.

`lifecycle.sh` is the only command-shaped orchestration layer. It owns
composite workflow sequencing, set locking, command summaries, and delegation
to the capability modules.

## Dependency Direction

The intended dependency direction is:

```text
simulate -> lifecycle
lifecycle -> docker-set/baseline/artifacts/roles/integration/ssh/state/config
docker-set/baseline -> compose/ports/state/config/paths
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

## Shared Extraction Rule

Symmetric placement makes comparable contracts visible, but symmetry alone is
not a reason to move code into `simulation/lib/`. Promote a helper only when
Docker and VM expose the same inputs, outputs, ownership boundary, and failure
semantics without backend conditionals. Public CLIs, command orchestration,
backend resource lifecycle, baseline mechanics, transport discovery, and
backend evidence collection remain separate.

## Refactor And Verification Policy

Structural refactor slices preserve public commands, options, terminal output,
generated paths, markers, evidence, cleanup behavior, and Docker waivers. Use
existing CLI tests as characterization coverage before changing internal APIs.
Run syntax, documentation, layout, terminal-summary, input-lifecycle,
artifact, role, integration, and cleanup tests for each slice. An end-to-end
Docker simulation is not required for behavior-preserving module movement and
remains subject to the execution ledger guardrail.
