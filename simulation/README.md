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

The simulation model derives account usage from `docs/account-model.md`. It
does not introduce a separate account taxonomy. The operator account is a
local OS account and uses `ci-operator` as the default example; it is not a
Gerrit or Jenkins product account.

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

Docker `clean` is manual and conservative: it removes mutable generated
runtime state while preserving exported artifact archives, evidence, and
logs.

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
