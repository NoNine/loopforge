# Gerrit/Jenkins Setup Package

This repository is the operator-facing v1 setup package for Gerrit, a Jenkins
controller, a Jenkins SSH build agent, LDAP-backed access, Gerrit Trigger
integration, and reviewable validation evidence.

Start with these references:

- `docs/prd.md` defines the product boundary and acceptance criteria.
- `docs/implementation-plan.md` defines the staged implementation plan.
- `docs/account-model.md` defines the runtime, admin, integration, test, bind,
  and simulation accounts.
- `docs/gerrit-setup-manual.md`,
  `docs/jenkins-controller-setup-manual.md`, and
  `docs/jenkins-agent-setup-manual.md` will hold the role setup manuals.
- `docs/gerrit-trigger-integration.md` will hold the Jenkins-to-Gerrit
  integration contract.
- `docs/validation-and-evidence.md` will hold validation and evidence rules.

## V1 Boundary

v1 is not a strict air-gapped installer. It does not support offline Ubuntu
dependency bundles. Target hosts may use approved internal Ubuntu/OS package
repositories for OS dependencies, but they must not download Gerrit or Jenkins
application artifacts from the public internet as a fallback.

Any public internet fallback for target-host Ubuntu/OS dependency installation
is simulation-only and must be labeled that way in documentation, logs, and
verification summaries.

Artifact preparation is separate from target-host installation. Prepared
Gerrit and Jenkins application artifacts, plugins, templates, manifests, and
checksums are staged to target hosts and verified before target mutation.

## Repository Layout

- `docs/` contains product references and operator manuals.
- `examples/` contains reviewed env-file examples with placeholder values.
- `scripts/` contains role helpers that will mirror manual phases.
- `templates/` contains Gerrit, Jenkins controller, Jenkins agent, job, and
  integration templates.
- `simulation/docker/` contains the first executable simulation model.
- `simulation/vm/` contains the later production-like verification model.
- `logs/` is a generated local runtime log directory. It is kept in git with a
  placeholder only; verbose runtime output must not be committed.

## Setup Flow

The planned flow is:

1. Review the product boundary and account model.
2. Create role env files from `examples/`.
3. Prepare curated application artifacts outside target-host installation.
4. Stage prepared artifacts to the target role hosts.
5. Follow the role manuals or matching helper commands for Gerrit, Jenkins
   controller, and Jenkins agent setup.
6. Configure Jenkins-to-Gerrit integration and agent registration.
7. Run validation and collect evidence with mode labels and bounded log
   references.

Helper command behavior is introduced in later implementation steps. Current
helper files are placeholders and must not be treated as implemented lifecycle
commands.
