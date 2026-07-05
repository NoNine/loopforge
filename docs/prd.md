# Loopforge Initial Experiment Environment PRD

## Summary
This document defines the product requirements for Loopforge's initial
Gerrit/Jenkins experiment environment.

Loopforge first provides a repeatable experiment environment for validating a
Gerrit/Jenkins integration stack, its setup workflow, and the evidence needed
to review the result. The product is not a strict air-gapped installer.
`target-deployment` environments may use reviewed public or upstream sources in
the bundle factory for curated application artifacts, and target hosts can use
approved internal Ubuntu/OS package repositories during setup. Public internet
fallback for target-host Ubuntu/OS dependency installation is simulation-only.

The product must help engineers and operators install and validate:

- Gerrit
- Jenkins controller
- Jenkins SSH build agent
- LDAP-backed identity integration
- Gerrit Trigger and `Verified` voting
- validation, logs, checksums, and audit evidence

## Goals
- Provide a repeatable experiment environment that operators can run from
  reviewed inputs.
- Keep the installation path deterministic enough for verification and audit.
- Make the package usable in target-deployment controlled environments.
- Preserve a clear manual procedure and a helper-script path that matches it.

## Non-Goals
- Strict air-gapped installation from removable media only
- Offline Ubuntu dependency bundle support
- General offline package management platform
- Helper commands for offline dependency bundle workflows
- Fleet OS patching or release-upgrade tooling
- High-availability or clustering
- TLS reverse-proxy implementation
- Enterprise secrets-manager integration
- Broad infrastructure orchestration outside the initial Gerrit/Jenkins
  experiment environment

## Product Requirements

### 1. Prerequisite Readiness
- The package must define required host prerequisites for Gerrit,
  Jenkins, and the build agent.
- The package must expose preflight checks for required commands, disk space,
  network reachability, LDAP reachability, and service-account readiness.
- The package must fail clearly when a prerequisite is missing.
- The package must document when a target host may use approved internal
  package sources and when simulation-only public fallback is allowed.

### 1.1. Product Behavior Modeling
- New or changed product behavior should document the intended
  `target-deployment` behavior before or alongside implementation.
- Simulation realization should model the normal product behavior as early as
  practical and as much as practical, including ownership boundaries,
  interfaces, lifecycle checkpoints, and evidence limits.
- Simulation-specific mechanisms must not bypass normal product operation to
  create success. Any explicit simulation-only waiver must be labeled,
  evidenced, and fail closed outside simulation modes.

### 2. Curated Artifact Preparation
- The product must support version-pinned application artifacts and plugins for
  Gerrit and Jenkins.
- The product must support config templates, env examples, and helper scripts
  for each service role.
- The product must produce checksums and bundle manifests for prepared
  artifacts.
- The product must keep artifact preparation separate from target-host
  installation.

### 2.1. Source Boundary
- Ubuntu/OS dependencies are packages installed through apt or equivalent OS
  package tooling, such as Java, SSH tools, service prerequisites, and OS
  libraries.
- Application artifacts include Gerrit WAR, Jenkins WAR, Gerrit/Jenkins
  plugins, JCasC/config templates, job definitions, manifests, and checksums.
  Application artifact bundles must not include actual SSH private keys,
  public keys, `authorized_keys`, or generated key/public-key handoff files.
  Jenkins-to-Gerrit and Jenkins-to-agent keypair generation and public-key
  handoff are integration-step work owned by the shared integration command
  surface, not by role-local artifact preparation.
- Target hosts may use approved internal Ubuntu/OS package repositories for
  OS dependencies during setup.
- Public internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only and must be labeled that way in docs, logs, and verification
  summaries.
- Target hosts must not download Gerrit/Jenkins application artifacts from the
  public internet as fallback.
- Application artifacts must be prepared in the bundle factory or staging
  environment, staged to target hosts, and verified by manifest and checksum
  before target-host mutation.
- v1 does not support offline Ubuntu dependency bundles.

### 3. Repeatable Service Installation
- Operators must be able to install Gerrit, Jenkins controller, and Jenkins
  build-agent with reviewed inputs for the initial experiment environment.
- The install path must support both manual commands and helper commands for
  preflight, artifact preparation, service install, integration, validation,
  and evidence collection.
- Helper commands must match the documented manual steps closely enough to
  serve as repeatable accelerators.
- Helper commands must not include supported offline dependency bundle
  workflows in v1.
- The installation flow must keep runtime, admin, and integration identities
  separate.
- Role helpers must stay role-local. Cross-role SSH, trigger setup,
  integration validation, trigger verification, and integration evidence are
  owned by `scripts/integration-setup.sh`.

### 4. Integration Configuration
- The package must configure LDAP-backed authentication assumptions.
- The package must support Jenkins-to-Gerrit SSH credentials and Gerrit
  integration permissions.
- The package must support Jenkins build-agent registration and validation.
- The package must support Gerrit Trigger behavior that posts back a
  `Verified` vote.
- The shared integration surface must preserve key custody: the Jenkins
  controller owns Jenkins-to-Gerrit and Jenkins-to-agent private keys; Gerrit
  and the Jenkins agent consume only the matching public keys.

### 5. Validation And Evidence
- The product must verify install and integration readiness.
- Validation must cover service startup, endpoint reachability, LDAP access,
  build-agent scheduling, and Gerrit Trigger voting.
- Validation must record checksums, package versions, config inputs, and the
  verification mode used.
- Evidence must distinguish target-deployment runs from simulation-only runs.
- Integration evidence must record public key fingerprints, credential IDs,
  accounts, endpoints, bounded logs, and redaction status only. It must not
  contain private keys, passwords, tokens, or LDAP bind secrets.

## Acceptance Criteria
- A new operator can follow the package docs and complete a repeatable setup
  without needing the repo history.
- Gerrit, Jenkins controller, and the Jenkins agent can be installed and
  started from the documented flow.
- LDAP auth and Gerrit/Jenkins integration can be configured successfully.
- Jenkins can schedule a job on the build agent and report back to Gerrit.
- Validation artifacts are produced and retained for review.
- The PRD does not claim strict air-gapped support in v1.

## Source Materials
This PRD is based on the current repo materials, especially:

- `docs/gerrit-native-operations-reference.md`
- `docs/jenkins-controller-native-operations-reference.md`
- `docs/jenkins-agent-native-operations-reference.md`
- `docs/integration-native-operations-reference.md`
- `docs/offline-bundle-verification.md`
- `docs/gerrit-jenkins-identity-model.md`
- `docs/air-gapped-ubuntu-package-strategy.md`
- `lab/README.md`
- `scripts/gerrit-operator.sh`
- `scripts/jenkins-operator.sh`
- `vm/scripts/vm-verify.sh`
