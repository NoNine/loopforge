# Simulation Model

This directory defines the shared simulation model for the v1 Gerrit/Jenkins
setup package. Layer-specific command ownership lives in the Docker and VM
README files; this file owns the common topology, source boundaries, output
conventions, and simulation realization details. `docs/lifecycle-contract.md`
owns checkpoint semantics for all modes.

The model has two layers:

1. Docker-based simulation first, owned by
   `simulation/docker/simulate.sh`.
2. VM-based simulation second.

Both layers use the same five-machine topology:

| Machine/environment | Docker form | VM form | Responsibility |
| --- | --- | --- | --- |
| Bundle factory | Container | VM | Runs role helper `prepare-artifacts` commands and produces curated application artifacts, plugins, manifests, and checksums. |
| LDAP | Container | VM | Hosts LDAP bind, admin, and test accounts and groups. |
| Gerrit | Container | VM | Runs Gerrit with LDAP authentication, SSH access, integration permissions, and the `Verified` label. |
| Jenkins controller | Container | VM | Runs Jenkins, LDAP/JCasC configuration, Gerrit Trigger, and agent registration. |
| Jenkins agent | Container | VM | Runs SSH build jobs scheduled by Jenkins. |

## Simulation Accounts

The simulation model derives account usage from `docs/account-model.md`. It
does not introduce a separate account taxonomy. Docker and VM simulation use
the account model's example target-local numeric identities by default:

| Account | Example name | Example UID/GID |
| --- | --- | --- |
| Operator account | `ci-operator` | `61000` |
| Gerrit runtime account | `gerrit` | `61010` |
| Jenkins controller runtime account | `jenkins` | `61020` |
| Jenkins agent runtime account | `jenkins-agent` | `61030` |
| Jenkins shared integration group | `jenkins-share` | no UID / `61040` |

The operator account is a local OS account on simulated targets and uses
`ci-operator` as the default example. It is not a Gerrit or Jenkins product
account, application admin account, integration account, LDAP bind account, or
test user account. Product runtime accounts own and run their services:
`gerrit` owns `/srv/gerrit`, `jenkins` owns `/var/lib/jenkins`, and
`jenkins-agent` owns `/var/lib/jenkins-agent`.

Jenkins controller and agent shared storage uses the separate
`jenkins-share` integration group, not a shared controller/agent UID.
`examples/integration.env.example` owns the default shared group name, GID,
and shared storage path. `scripts/integration-setup.sh` owns creating or
validating that group on both Jenkins targets, adding the controller and agent
runtime accounts to it, setting setgid group-writable storage permissions, and
recording read/write proof. Role-local helpers do not own shared storage
setup.

Simulation targets provide a target-local `ci-operator` account with
passwordless sudo for simulation orchestration and privileged helper
operations. Privileged operations are still delegated privilege from the
operator account for narrow OS work; root is not a Loopforge account, helper
execution identity, runtime identity, or supported direct login identity. The
local host account that invokes a simulation `simulate.sh` may have any
site-local name and is not renamed, mapped, or required to be `ci-operator`.

Docker and VM `status` commands may print seeded human login accounts for
their simulation LDAP and product environments. The Jenkins Gerrit integration
account is different: it is created or validated later as a Gerrit service
account by the shared integration step, not seeded as an LDAP password user.

Docker and VM `ssh --role ROLE` commands intentionally use target OS
control-plane SSH as the target-local operator account. They are separate from
Gerrit's service SSH on port `29418` and from layer-specific backdoors such as
Docker exec or libvirt console access.

## Version Baseline

`docs/version-baseline.md` owns the default version baseline for both
simulation layers. Future verifiers must fail or report blocked rather than
claim comparable readiness when the Ubuntu, Java, Gerrit, Jenkins controller,
plugin-manager, or Jenkins agent/plugin-bundle versions differ from the
reviewed baseline.

## Source Boundaries

Ubuntu/OS dependencies and application artifacts are separate supply lanes.
Target hosts may use approved internal Ubuntu/OS package repositories for OS
dependencies. Application artifacts are prepared only in the bundle factory,
then staged to Gerrit, Jenkins controller, and Jenkins agent target/service
environments and verified by manifest and checksum before mutation.

Public internet fallback for target-host Ubuntu/OS dependency installation is
simulation-only and must be labeled `simulation-only` in docs, logs, and
verification summaries. Target hosts must not download Gerrit/Jenkins
application artifacts from the public internet as fallback. In v1, offline
Ubuntu dependency bundle workflows are not supported.

## Output Locations

Generated runtime output is not committed. Docker v1 writes lifecycle output
under a single repo-local generated run root so lifecycle and cleanup commands
share the same path contract:

```text
generated/simulation/docker/<run-id>/
```

Docker lifecycle and cleanup commands do not support arbitrary generated
roots in v1. Use a distinct run ID to isolate separate runs.

VM simulation writes reusable VM-set state and run-scoped output under the
repo-local VM generated root. VM set state persists across runs until explicit
destruction, while run-scoped output is tied to `HARNESS_RUN_ID`:

```text
generated/simulation/vm/vm-sets/<vm-set-id>/
generated/simulation/vm/<run-id>/
```

Docker uses these subpath patterns:

| Output kind | Run-scoped pattern |
| --- | --- |
| State | `generated/simulation/docker/<run-id>/target/helper-state/` |
| Product runtime homes | `generated/simulation/docker/<run-id>/target/product-homes/` |
| Staged artifacts | `generated/simulation/docker/<run-id>/target/artifacts/staging/<role>/` |
| Exported artifacts | `generated/simulation/docker/<run-id>/target/artifacts/exported/<bundle>.tar.gz` |
| Harness evidence | `generated/simulation/docker/<run-id>/host/evidence/harness/` |
| Harness bounded logs | `generated/simulation/docker/<run-id>/host/logs/harness/` |
| Integration evidence and logs | `generated/simulation/docker/<run-id>/host/evidence/integration/`, `host/logs/integration/` |
| Target role evidence | `generated/simulation/docker/<run-id>/target/evidence/<role>/` |
| Target role bounded logs | `generated/simulation/docker/<run-id>/target/logs/<role>/` |

`<run-id>` is a unique run identifier, such as a UTC timestamp plus a short
label. `<environment>` is one of `bundle-factory`, `ldap`, `gerrit`,
`jenkins-controller`, or `jenkins-agent`.

These paths are generated runtime output unless a file in the tree states
otherwise. Keep them ignored or documented as generated when created by
simulation steps.

Simulation cleanup is manual and conservative. Cleanup commands remove or
reset mutable generated runtime state for the selected run while preserving
exported artifact archives, evidence, and logs. Layer-specific cleanup
commands may additionally stop containers, roll back VMs, or use retained
output backup snapshots, but they must not silently discard review evidence.

## Shared Command Semantics

Layer README files own the concrete command reference for their entrypoint.
When a layer uses these command names, the shared simulation semantics are:

| Command | Shared meaning |
| --- | --- |
| `run` | Normal workflow composite for the selected run. It does not run cleanup, teardown, destruction, or audit commands. |
| `preflight` | Read-only prerequisite check before service mutation. |
| `init-run` | Input review/rendering, private runtime input copy creation, and selected run marker creation. |
| `up` | Start or attach the selected simulation environment after rendered run state exists. |
| `status` | Read-only inspection of selected live simulation state. |
| `ssh` | Operator-account target OS control-plane SSH, not Gerrit service SSH. |
| `prepare-artifacts` | Artifact preparation through role helpers in the bundle factory. |
| `stage-artifacts` | Artifact transfer plus target-side manifest/checksum verification before service mutation. |
| `configure-role` | Role-local setup for one or all service roles. |
| `validate-role` | Role-local readiness validation only; no cross-role success claim. |
| `configure-integration` | Shared integration setup through `scripts/integration-setup.sh`. |
| `validate-integration` | Passive cross-role readiness validation. |
| `prove-integration` | Active end-to-end trigger proof after matching validation passed. |
| `audit-state` | Explicit read-only generated-state and environment consistency inspection. |
| `down` | Stop the selected simulation environment while retaining review output. |
| `clean` | Reset mutable selected-run state while preserving retained artifacts, evidence, and logs. |

Layers may add simulation-specific lifecycle commands, such as VM `create`,
`reboot`, or `destroy`, but unsupported or unavailable proof must fail closed
or report blocked rather than produce synthetic success.

## Input And Secret Handling

Simulation harnesses copy selected harness, role, and integration input files
into private run-scoped runtime input locations during `init-run`. The
redacted public record is for inspection; private runtime env files retain
lifecycle values and point at the runtime input copies. Full reviewed helper
env files remain operator inputs and are transferred only to helper execution
input locations. They are not helper-owned state and must not be embedded in
artifact bundles.

Docker and VM simulation may use simulation-owned fake LDAP bind passwords for
their own LDAP environments. The default example values are not real
organization secrets and must not be replaced with real organization LDAP
secrets. Harnesses redact those values from rendered summaries, runtime input
copies, helper env files, logs, evidence, and artifact bundles, then inject
them only into helper command environments for commands that need LDAP proof or
product runtime configuration. Product runtime config files may still persist
product-required LDAP settings after the relevant role helper writes them.

## Harness And Helper Boundary

Simulation harnesses provide the environment work they must provide: generated
run roots, reviewed input custody, environment lifecycle, network or SSH
control-plane access, and explicitly labeled simulation transfer waivers.
Role helpers still own role-local lifecycle work inside helper-visible paths,
including creation of `/var/lib/loopforge` and `/var/log/loopforge`, artifact
preparation, target-local mutation, validation, and evidence collection.

Artifact preparation writes role artifacts and archive pairs in the bundle
factory. Artifact staging transfers archive pairs to target environments
through a layer-specific, labeled transfer mechanism, then verifies manifest
and checksum data on the target side under `/var/lib/loopforge/staging`
before service mutation. Simulation backing paths and transfer mechanisms may
support this lifecycle, but helper-visible paths remain product-like.

Target operations still install or update native product-owned paths such as
`/srv/gerrit`, `/var/lib/jenkins`, `/var/lib/jenkins-agent`,
`$JENKINS_HOME/.ssh/known_hosts`, and agent `authorized_keys`. Transient
target-local files under `/tmp` are acceptable when they stage payloads for
normal target APIs or runtime installation, but they must not bypass reviewed
helper inputs or helper-owned state.

Generated evidence, logs, and exported artifacts may be collected for review.
Jenkins-owned private keys under integration key storage are the deliberate
exception to host-side custody: the Jenkins controller owns Jenkins-to-Gerrit
and Jenkins-to-agent private keys, while generated scripts, status files,
evidence, and public-key metadata remain harness or integration sideband
state.

## State Consistency And Recovery

A selected simulation run is consistent only when its generated run marker,
rendered runtime config, runtime input copies, fingerprints, and selected
environment markers agree. Runtime input copies must exist for the harness,
Gerrit, Jenkins controller, Jenkins agent, and integration env files before
phases that need them. Layer-specific checks add Docker bind-mount liveness or
VM-set ownership and snapshot validation.

If generated state, environment ownership metadata, bind mounts, snapshots, or
other selected lifecycle state are inconsistent, lifecycle phases fail clearly
instead of recreating state or rerunning earlier phases. Recovery must use the
explicit layer cleanup or teardown commands for the selected run or selected
VM set.

## Lifecycle Realization

`docs/lifecycle-contract.md` defines checkpoint semantics, pass/block
conditions, mutation boundaries, and evidence obligations. Simulation layers
may split, collapse, or add simulation-only commands, but they must preserve
that contract and keep terminal output short.

Simulation-specific realization notes:

- `preflight` checks local tooling, command surfaces, run naming, and
  version/source-boundary constraints before service mutation.
- Input rendering records the exact operator-selected config for a run,
  including redacted env values and layer-specific rendered inputs.
- Artifact preparation runs role helper `prepare-artifacts` commands in the
  bundle factory.
- Artifact staging verifies manifest and checksum data on the target side
  before service mutation.
- Readiness checks must be real runtime checks. Role-local readiness does not
  claim cross-role trigger success.
- End-to-end execution must prove Gerrit event receipt, Jenkins job
  scheduling, agent execution, and Gerrit `Verified +1`.
- Evidence audit summarizes retained proof without rerunning the workflow.

Role helpers stay role-local in both layers. Cross-role SSH, trigger setup,
integration validation, trigger verification, and integration evidence use
`scripts/integration-setup.sh`. Scaffold-level integration commands must fail
closed until a real Docker or VM implementation exists.
