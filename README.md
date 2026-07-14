# Loopforge

Loopforge is an experiment environment package for building and verifying a
Gerrit/Jenkins integration stack. It models Gerrit, a Jenkins controller, a
Jenkins SSH build agent, LDAP-backed identity, Gerrit Trigger integration,
`Verified` voting, and reviewable validation evidence.

The first user-facing surface is the Docker simulation. It gives operators a
repeatable way to exercise the setup flow before moving into VM simulation or
target-deployment documentation.

## What You Can Do

- Run the Docker simulation from one CLI entrypoint.
- Prepare and stage reviewed Gerrit, Jenkins controller, and Jenkins agent
  artifacts before service mutation.
- Validate role readiness, cross-role integration, agent scheduling, and
  Gerrit `Verified` voting.
- Review generated evidence, checksums, bounded log references, and redaction
  summaries.
- Use the role manuals as the source of truth for target-oriented setup steps.

## Architecture At A Glance

```text
+---------------------------------------------------------------+
| Operator workstation / control node                           |
| Runs harness/helpers and coordinates setup and validation     |
+---------------------------------------------------------------+
      |                        |                        |
      v                        v                        v
+-----------+       +--------------------+       +--------------+
| Gerrit    |<----->| Jenkins controller |<----->| Jenkins agent|
+-----------+       +--------------------+       +--------------+
      ^                        ^                        ^
      |                        |                        |
      +------------------------+------------------------+
                               |
                    +----------------------+
                    | Bundle factory       |
                    | Prepares artifacts   |
                    +----------------------+

+---------------------------------------------------------------+
| LDAP                                                          |
| Shared identity service                                       |
+---------------------------------------------------------------+
```

Docker, VM, and target-deployment modes realize the same logical environments
with different infrastructure boundaries. Detailed interfaces are documented
in `docs/architecture/system-model.md`; phase order and checkpoint behavior are documented
in `docs/contracts/lifecycle-contract.md`.

## Docker Simulation Flow

```mermaid
flowchart LR
  subgraph run[run]
    preflight[preflight]
    initRun[init-run]
    up[up]
    status[status]
    prepare[prepare-artifacts]
    stage[stage-artifacts]
    configureRole[configure-role]
    validateRole[validate-role]
    configureIntegration[configure-integration]
    validateIntegration[validate-integration]
    proveIntegration[prove-integration]
  end
  down[down]
  clean[clean]

  preflight --> initRun --> up --> status --> prepare --> stage --> configureRole --> validateRole --> configureIntegration --> validateIntegration --> proveIntegration --> down --> clean
```

## Host Requirements

Run the local harness on a Linux host with:

- Python 3.9+
- Docker Engine
- Docker Compose
- Enough disk space for `generated/` and `logs/`

See `docs/baselines/package-requirements.md` for mode-based host prerequisites and the
package matrix.

## Start With Docker Simulation

The Docker simulation CLI is the first executable entrypoint:

```bash
simulation/docker/simulate.sh run
```

`run` is the normal operator workflow. It reports `fresh` or `resume` and
then drives the expanded phase sequence through `prove-integration`.

After `up`, open host-to-target OS SSH sessions for inspection:

```bash
simulation/docker/simulate.sh ssh --role gerrit
simulation/docker/simulate.sh ssh --role jenkins-controller
simulation/docker/simulate.sh ssh --role jenkins-agent
```

These sessions use the rendered target SSH inventory and the simulation
`ci-operator` OS account, not Docker exec or Gerrit service SSH.

After inspection, stop containers or remove generated runtime state:

```bash
simulation/docker/simulate.sh down
simulation/docker/simulate.sh clean
```

`down` stops harness containers while preserving generated state for review.
Use `clean` when generated runtime state should be removed.

To use a copied harness env file instead of the default example, pass
`--env FILE` to each command. See `simulation/docker/README.md` for command
details, phase commands, inputs, outputs, generated paths, and simulation
accounts.

## Repository Map

```text
.
├── AGENTS.md             # AI coding-agent instructions for this repository
├── docs/                 # Product, architecture, contracts, operations, and plans
├── examples/             # Reviewed env-file examples with placeholder values
├── project-state/        # Mutable implementation resume ledger
├── scripts/              # Role helpers, integration setup, and evidence collection
├── simulation/           # Shared simulation model and mode-specific harnesses
│   ├── docker/           # Docker simulation CLI, Compose file, and operator docs
│   └── vm/               # Planned VM simulation model and command contract
├── templates/            # Gerrit, Jenkins, agent, job, and integration templates
├── tests/                # Repository validation and contract tests
├── generated/            # Generated simulation/runtime output; not committed
└── logs/                 # Bounded local command logs; not committed
```

## Documentation Guide

AI agents and reviewers should start with `docs/README.md` when a
change affects documentation ownership, source-of-truth boundaries, or
cross-document consistency. It defines the layered authority model and the
review checklist for docs changes.

Scope and model:

- `docs/product/prd.md` defines product goals, non-goals, requirements, and acceptance
  criteria.
- `docs/architecture/system-model.md` defines environments, actors, accounts, utilities,
  interfaces, deployment modes, and evidence relationships.
- `docs/contracts/lifecycle-contract.md` defines phase order, lifecycle checkpoints,
  mutation boundaries, resume/rerun behavior, and command mapping.

Topic references:

- `docs/contracts/account-model.md` defines runtime, admin, integration, test, bind, and
  simulation accounts.
- `docs/contracts/directory-model.md` defines product homes, helper-owned state,
  artifact extraction paths, runtime scratch, and simulation backing.
- `docs/baselines/version-baseline.md` defines the default Ubuntu, Java, Gerrit,
  Jenkins, plugin-manager, and Jenkins agent/tooling baseline.
- `docs/baselines/package-requirements.md` defines layered Ubuntu package requirements
  for product runtimes, helper scripts, bundle factory, and Docker simulation.
- `docs/contracts/artifact-bundle-contract.md` defines application artifact archive
  contents, checksums, source boundaries, and bundle-factory dependencies.
- `docs/contracts/gerrit-trigger-integration.md` defines Gerrit Trigger, ACL, and
  `Verified` voting behavior.
- `docs/contracts/validation-and-evidence.md` defines validation evidence and redaction
  rules.

Simulation:

- `simulation/README.md` defines the shared simulation topology, version
  baseline, output conventions, and simulation realization details.
- `simulation/docker/README.md` documents the Docker simulation CLI command
  surface.
- `simulation/vm/README.md` documents the VM simulation CLI command surface.

Operator manuals:

- `docs/operations/setup/gerrit.md`,
  `docs/operations/setup/jenkins-controller.md`, and
  `docs/operations/setup/jenkins-agent.md` document role-local setup.
- `docs/operations/setup/integration.md` documents the shared cross-role
  integration workflow.

Native operation references:

- `docs/operations/native/gerrit.md`,
  `docs/operations/native/jenkins-controller.md`, and
  `docs/operations/native/jenkins-agent.md` document direct role-local
  procedures.
- `docs/operations/native/integration.md` documents direct cross-role
  integration procedures.
