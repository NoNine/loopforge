# Docker Simulation State Lifecycle

This document defines how Docker simulation commands treat generated state and
existing Compose containers. It applies the general operator workflow rule from
`docs/system-model.md`: each phase checks its prerequisites, performs
only its own phase work, and fails clearly instead of rerunning other phases.

Docker simulation state is run-scoped under:

```text
generated/simulation/docker/<run-id>/
```

## Terms

Selected Compose project means the project identified by the selected harness
env and run configuration. For the default simulation, the project name is
`gerrit-jenkins-harness`.

Containers exist when any expected service container for the selected Compose
project exists, whether it is running or stopped. The expected services are:

- `bundle-factory`
- `ldap`
- `gerrit-target`
- `jenkins-controller-target`
- `jenkins-agent-target`

Fresh workflow means starting a new Docker simulation run at `init-run`.
`preflight` is recommended before `init-run`, but it is not required.
`preflight` validates local tooling and static harness inputs; it does not
replace rendered runtime config.

Resume or rerun means invoking a lifecycle phase against an existing selected
run, such as `up`, `status`, `prepare-artifacts`, `stage-artifacts`,
`configure-role`, `validate-role`, `configure-integration`,
`validate-integration`, or `prove-integration`.

## Required Generated State

`init-run` is the first phase that creates runtime configuration required
by later lifecycle phases. Later phases must fail clearly with an instruction
to run `init-run` first when selected runtime config is missing.

A selected generated run is consistent only when the core run state exists and
matches the selected run:

- The canonical run root exists under `generated/simulation/docker/<run-id>/`.
- The generated run marker exists.
- `host/rendered/harness.env` exists.
- `host/rendered/harness.runtime.env` exists.
- The runtime env fingerprint matches the generated run marker.
- `host/runtime-inputs/` exists.
- Runtime input copies exist for the harness, Gerrit, Jenkins controller,
  Jenkins agent, and integration env files.
- Helper env files under `host/runtime-inputs/helper-envs/` exist
  for phases that need them.
- Expected generated bind source directories exist before container lifecycle
  phases use them.

When selected containers already exist, resume/rerun must also validate that
container bind mounts still point at the selected canonical run root. A host
probe written to each required bind source must be visible at the expected
container destination before a phase relies on that mount.

If either generated state or bind-mount liveness is inconsistent, lifecycle
phases must fail clearly instead of recreating state or rerunning prior phases.
The user must recover with `down` or `clean`.

## Case Matrix

| Situation | Expected behavior |
| --- | --- |
| Fresh repo state: no selected containers and no generated run state | `init-run` may create the selected generated run state. `up` requires that rendered runtime config already exists. |
| Selected containers exist and generated bind mounts match the selected run | Resume/rerun phases may continue after validating their own prerequisites. Use `audit-state` for the explicit bind-mount audit when needed. |
| Selected containers exist but `generated/` was removed or recreated | Resume/rerun phases must fail clearly because existing containers are bound to missing or stale host paths. Use `down` or `clean` recovery before starting again. |
| No selected containers exist but a previous generated folder remains | `init-run` may create or overwrite generated runtime config for the selected run. Later phases use the newly rendered state. |
| Partial or inconsistent generated state exists | Lifecycle phases must fail clearly. If containers exist, use `down` or `clean` recovery. If no containers exist, rerun `init-run` to create a consistent run. |

## Down And Clean Recovery

`down` stops and removes selected simulation containers while retaining
generated output for review. It must support bootstrap-only recovery when
generated runtime config is missing or inconsistent, because stale containers
may be the problem being recovered from.

`clean` may share the same container cleanup recovery as `down`. It must not
delete generated files outside the canonical run root. If runtime config is
missing or inconsistent but the canonical run root still exists, `clean` may
remove selected containers, remove known mutable generated paths, back up
retained outputs, and clear active retained output directories. If the
canonical run root is missing, it must report that host generated cleanup was
skipped.

Retained output backups are host-dominated review copies under
`host/retained-output-backups/<timestamp>/` and are host-owned. Active target
role evidence and log directories under `target/evidence/<role>/` and
`target/logs/<role>/` remain target-dominated while active; `clean` must not
normalize them to host ownership in place before a later run reuses the same
directories.

Example recovery after deleting bind mounts while containers still exist:

```bash
rm -rf generated/
simulation/docker/simulate.sh down
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh up
```

Equivalent recovery when housekeeping is desired:

```bash
rm -rf generated/
simulation/docker/simulate.sh clean
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh up
```

In both examples, `down` and `clean` are the only phases allowed to recover
from stale existing containers. Other phases should report the inconsistent
state and stop.

## Verify State

`audit-state` is the explicit read-only command for the expensive container
and bind-mount sweep. It checks the live selected containers against the
selected run root and is meant for operator inspection, not for the default
path of `status`, `configure-role`, `validate-role`, `configure-integration`,
`validate-integration`, `prove-integration`, `prepare-artifacts`, or
`stage-artifacts`.
