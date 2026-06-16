# Gerrit/Jenkins Setup Package PRD

## Summary
This document defines the v1 product requirements for a repeatable
Gerrit/Jenkins setup package.

The product is not a strict air-gapped installer. v1 supports installation in
controlled environments where staging can use reviewed public or upstream
sources for curated application artifacts, and target hosts can use approved
internal Ubuntu/OS package repositories during setup. Public internet fallback
for target-host Ubuntu/OS dependency installation is simulation-only.

The product must help engineers and operators install and validate:

- Gerrit
- Jenkins controller
- Jenkins SSH build agent
- LDAP-backed identity integration
- Gerrit Trigger and `Verified` voting
- validation, logs, checksums, and audit evidence

## Goals
- Provide a repeatable setup flow that operators can run from reviewed inputs.
- Keep the installation path deterministic enough for verification and audit.
- Make the package usable in production-like controlled environments.
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
- Broad infrastructure orchestration outside Gerrit/Jenkins setup

## Product Requirements

### 1. Prerequisite Readiness
- The setup package must define required host prerequisites for Gerrit,
  Jenkins, and the build agent.
- The package must expose preflight checks for required commands, disk space,
  network reachability, LDAP reachability, and service-account readiness.
- The package must fail clearly when a prerequisite is missing.
- The package must document when a target host may use approved internal
  package sources and when simulation-only public fallback is allowed.

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
  plugins, JCasC/config templates, job definitions, generated key/public-key
  handoff files, manifests, and checksums.
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
  build-agent with reviewed inputs.
- The install path must support both manual commands and helper commands for
  preflight, artifact preparation, service install, integration, validation,
  and evidence collection.
- Helper commands must match the documented manual steps closely enough to
  serve as repeatable accelerators.
- Helper commands must not include supported offline dependency bundle
  workflows in v1.
- The installation flow must keep runtime, admin, and integration identities
  separate.

### 4. Integration Configuration
- The package must configure LDAP-backed authentication assumptions.
- The package must support Jenkins-to-Gerrit SSH credentials and Gerrit
  integration permissions.
- The package must support Jenkins build-agent registration and validation.
- The package must support Gerrit Trigger behavior that posts back a
  `Verified` vote.

### 5. Validation And Evidence
- The product must verify install and integration readiness.
- Validation must cover service startup, endpoint reachability, LDAP access,
  build-agent scheduling, and Gerrit Trigger voting.
- Validation must record checksums, package versions, config inputs, and the
  verification mode used.
- Evidence must distinguish production-like runs from simulation-only runs.

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

- `docs/gerrit-install-air-gapped.md`
- `docs/jenkins-install-air-gapped.md`
- `docs/jenkins-agent-install-air-gapped.md`
- `docs/offline-bundle-verification.md`
- `docs/gerrit-jenkins-identity-model.md`
- `docs/air-gapped-ubuntu-package-strategy.md`
- `lab/README.md`
- `scripts/gerrit-operator.sh`
- `scripts/jenkins-operator.sh`
- `vm/scripts/vm-verify.sh`
