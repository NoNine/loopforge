# Jenkins Controller Setup Manual

This manual is the authority for the Jenkins controller role. The helper
`scripts/jenkins-controller-setup.sh` is a repeatable accelerator for reviewed
env files; it does not replace operator review.

Maintain this manual with
`docs/jenkins-controller-native-operations-reference.md`. The native reference
is the strong reference for direct OS and Jenkins controller operations and
must remain free of repository helper commands.

The v1 boundary is unchanged: Jenkins application artifacts, plugin artifacts,
JCasC templates, job templates, manifests, and checksums are prepared in the
bundle factory, staged to the Jenkins controller target, and verified by
manifest and checksum before target mutation. v1 does not support offline
Ubuntu dependency bundle workflows. Any public internet fallback for
target-host Ubuntu/OS dependency installation is simulation-only and must be
labeled that way in logs and evidence.

Default baseline:

| Item | Default |
| --- | --- |
| Ubuntu target | 24.04.4 LTS, release `24.04`, codename `noble` |
| Java | OpenJDK 21 |
| Jenkins controller | 2.555.3 LTS |
| Jenkins Plugin Installation Manager Tool | 2.15.0 |

## Phase 1: Operator Inputs

Consumed inputs:

- `examples/jenkins-controller.env.example` copied to a reviewed local env
  file.
- Jenkins URL, host, HTTP port, runtime account, and Jenkins home path.
- LDAP URL, read-only bind DN, user base, group base, Jenkins admin account,
  and Jenkins admin group.
- Gerrit HTTP URL, SSH host and port, Gerrit Trigger server name, Jenkins
  Gerrit integration account, and Jenkins credential ID.
- Jenkins build-agent host, SSH port, runtime account, label, remote
  filesystem, and Jenkins credential ID.
- Controller-owned Jenkins-to-Gerrit private-key path and public-key handoff
  path.
- Controller-owned Jenkins-to-agent private-key path and public-key handoff
  path.
- Artifact output path, staged artifact path, verification mode, evidence
  directory, and bounded log directory.
- `JENKINS_PLUGIN_LIST`, with curated `name:version` plugin entries.
- `JENKINS_OS_DEPENDENCIES`, which defaults to controller target OS package
  expectations from the approved Jenkins reference: `ca-certificates`, `curl`,
  `fontconfig`, `git`, `net-tools`, `netcat-openbsd`, `openjdk-21-jre`,
  `openssh-client`, `rsync`, `tar`, `unzip`, and `wget`.

Produced outputs:

- Reviewed Jenkins controller env file.
- Sanitized input fingerprint in evidence.

Side effects:

- Local env-file review only. No Jenkins target mutation.

Helper:

```bash
scripts/jenkins-controller-setup.sh print-env-template
```

Secret-redaction expectations:

- Evidence must not record private keys, passwords, tokens, LDAP bind secrets,
  or full secret-bearing env values.
- Evidence may record public key fingerprints, credential IDs, account names,
  endpoints, manifest paths, checksum paths, and bounded log references.

## Phase 2: Prerequisite Readiness

Consumed inputs:

- Reviewed Jenkins controller env file.
- Target host baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21 expectation,
  approved internal Ubuntu/OS package repositories, reachable LDAP, reachable
  Gerrit SSH, and reachable Jenkins agent SSH assumptions.
- Jenkins OS dependency expectations listed in Phase 1.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline
  values, endpoint values, LDAP assumptions, Gerrit SSH assumptions, agent
  values, and artifact paths.
- OS dependency expectation checks for the package/tooling names above.

Side effects:

- None. Preflight is non-mutating.
- The helper does not provide offline Ubuntu dependency bundle commands.
  Target hosts may use approved internal Ubuntu/OS package repositories.
  Public internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> preflight
```

For dry-run review:

```bash
scripts/jenkins-controller-setup.sh --env examples/jenkins-controller.env.example --dry-run preflight
```

## Phase 3: Curated Jenkins Controller Artifact And Plugin Preparation

Artifact preparation runs in the bundle factory environment, not on the
Jenkins controller target. The shared Docker harness runs this phase in the
bundle factory container for Step 8 validation.

Consumed inputs:

- Reviewed Jenkins controller env values.
- Version baseline: Jenkins 2.555.3 LTS, OpenJDK 21, Jenkins Plugin
  Installation Manager Tool 2.15.0, Ubuntu release `24.04`, codename `noble`.
- Curated Jenkins plugin list with versions.
- Jenkins controller templates under `templates/jenkins-controller/`.

Produced outputs:

- `manifest.txt`.
- `checksums.sha256`.
- Curated Jenkins WAR marker for the Docker harness role gate.
- Curated Jenkins Plugin Installation Manager Tool marker.
- Curated Jenkins plugin markers named from reviewed plugin IDs.
- JCasC, credential, Gerrit Trigger, agent-node, service, and disposable
  verification templates.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `JENKINS_ARTIFACT_OUTPUT_DIR` |
| Docker harness bundle output | `/harness/state/artifacts/jenkins-controller` inside the bundle factory |
| Docker harness host state | `simulation/state/docker/harness/<run-id>/bundle-factory/artifacts/jenkins-controller/` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- Does not install, configure, or start Jenkins.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> prepare-artifacts
```

Harness:

```bash
simulation/docker/docker-harness.sh prepare-artifacts --role jenkins-controller
```

## Phase 4: Jenkins Installation

Installation consumes only staged bundle factory output. The target verifies
`manifest.txt` and `checksums.sha256` before mutation.

Consumed inputs:

- Reviewed Jenkins controller env file.
- Staged artifact directory, normally `/harness/staged` in the Docker role
  gate.
- `manifest.txt` and `checksums.sha256`.

Produced outputs:

- Jenkins home tree under `JENKINS_HOME`.
- `war/jenkins.war`.
- `war/jenkins-plugin-manager.jar`.
- Staged templates under `templates/`.
- `artifact-manifest.txt` and `artifact-checksums.sha256`.
- Install marker under `state/install.status`.

Mutation side effects:

- Creates or updates Jenkins role-local home files.
- Does not download Jenkins application artifacts on the target.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes install
```

## Phase 5: Jenkins Runtime Configuration

Consumed inputs:

- Reviewed Jenkins controller env file.
- Staged service template.
- Jenkins runtime account, home path, HTTP port, and JCasC location.

Produced outputs:

- Rendered service environment file.
- Service configuration marker.
- Real Jenkins controller runtime configuration ready to start from the staged
  Jenkins WAR, plugin set, JCasC material, and reviewed HTTP port.

Mutation side effects:

- Creates or updates Jenkins role-local runtime service settings.
- Production-like service management remains an operator-controlled action.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes configure-service
```

## Phase 6: LDAP/JCasC Configuration

Jenkins uses LDAP-backed human admin access. The Jenkins runtime account and
Jenkins Gerrit integration account remain separate from the Jenkins admin
account or group.

Consumed inputs:

- LDAP URL.
- Read-only LDAP bind DN.
- User and group bases.
- Jenkins admin account and group.
- Staged JCasC template.

Produced outputs:

- Rendered JCasC file with LDAP security realm and zero built-in executors.
- JCasC readiness marker.

Mutation side effects:

- Creates or updates role-local Jenkins JCasC material.
- Records non-secret LDAP metadata only. Operators must provide real bind
  secrets through reviewed secret handling outside evidence.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes configure-jcasc
```

Plugins are installed from staged curated artifacts before JCasC validation:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes install-plugins
```

## Phase 7: Gerrit Trigger Base Configuration

Consumed inputs:

- Jenkins Gerrit integration account.
- Jenkins Gerrit credential ID.
- Gerrit HTTP URL, SSH host, SSH port, and Gerrit Trigger server name.
- Staged credentials and Gerrit Trigger templates.
- Controller-owned Jenkins-to-Gerrit private key and public key generated in
  Phase 8.

Produced outputs:

- Rendered Jenkins credentials material referencing the credential IDs.
- Rendered Gerrit Trigger server configuration.
- Gerrit Trigger readiness marker.

Mutation side effects:

- Creates or updates Jenkins role-local credential and Gerrit Trigger config.
- Does not write private key material into evidence.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes configure-integration
```

## Phase 8: Jenkins-To-Gerrit SSH Key Generation

Consumed inputs:

- Reviewed controller-owned private-key path.
- Public-key handoff path for Gerrit.
- Jenkins Gerrit integration account name.

Produced outputs:

- Jenkins-to-Gerrit private key owned by the Jenkins controller workflow.
- Jenkins-to-Gerrit public key handoff file for Gerrit.
- Public key fingerprint in status and evidence.

Key handoff:

- Jenkins controller retains the private key.
- Gerrit consumes only the public key through the Gerrit helper integration
  workflow.

Mutation side effects:

- Creates or rotates the controller-held Jenkins-to-Gerrit keypair.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes generate-integration-key
```

## Phase 9: Build-Agent SSH Key Generation

Consumed inputs:

- Reviewed controller-owned agent private-key path.
- Public-key handoff path for the Jenkins agent host.
- Jenkins agent account name.

Produced outputs:

- Jenkins-to-agent private key owned by the Jenkins controller workflow.
- Jenkins-to-agent public key handoff file for the agent helper.
- Public key fingerprint in status and evidence.

Key handoff:

- Jenkins controller retains the private key.
- Jenkins agent consumes only the public key through the agent helper runtime
  workflow.

Mutation side effects:

- Creates or rotates the controller-held Jenkins-to-agent keypair.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes generate-agent-key
```

## Phase 10: Build-Agent Registration And Scheduling Validation

Consumed inputs:

- Jenkins agent host, SSH port, runtime account, label, remote filesystem, and
  credential ID.
- Controller-held Jenkins-to-agent private key.
- Public-key handoff path for the agent host.
- Staged agent-node template.

Produced outputs:

- Rendered Jenkins agent node config.
- Agent registration marker.
- Jenkins controller-side node registration state.
- `validate-agent` must either run a real controller-to-agent scheduling check
  against the configured SSH agent or exit nonzero with a clear blocked or
  unsupported status.

Mutation side effects:

- Creates or updates Jenkins role-local node configuration.
- `validate-agent` must not pass with a modeled scheduling record. Real
  scheduling belongs to the Jenkins controller helper, while the agent helper
  owns only host-side SSH readiness.

Helpers:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes configure-agent
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes validate-agent
```

## Phase 11: End-To-End Gerrit Trigger Verification

Consumed inputs:

- Gerrit Trigger server configuration.
- Step 8 modeled agent scheduling record from Phase 10.
- Disposable Gerrit project, branch, and verification run ID.
- Disposable verification job template.

Produced outputs:

- Disposable verification job config and trigger inputs.
- Gerrit Trigger verification evidence from real Jenkins/Gerrit interaction,
  or a nonzero blocked/unsupported result when the real interaction cannot run.

Mutation side effects:

- Creates disposable verification templates and records the real verification
  result for the reviewed run ID.
- Docker harness mode must not pass with modeled `patchset-created`, agent
  build, or `Verified +1` voting. If the role gate cannot complete the real
  verification at this step, it must fail or report blocked. Step 11 remains
  the full cross-role Docker gate that aggregates the same real workflow across
  all five environments.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes verify-trigger
```

Failure classification follows `docs/gerrit-trigger-integration.md`: SSH
credential failures, `stream-events` failures, job/agent scheduling failures,
and `Verified` voting failures must remain distinct.

## Phase 12: Validation

Validation in Step 8 proves Jenkins controller role readiness with real runtime
checks for the lifecycle phases that report success. It verifies staged
artifacts, rendered configuration, curated plugins, keys, LDAP reachability,
Gerrit SSH reachability, Jenkins controller startup, Gerrit Trigger readiness,
agent scheduling when `validate-agent` reports success, and trigger voting when
`verify-trigger` reports success. Unimplemented lifecycle phases must exit
nonzero with a clear blocked or unsupported status.

Consumed inputs:

- Reviewed Jenkins controller env file.
- Staged artifact manifest and checksums.
- Installed Jenkins home files and rendered configuration.

Validation evidence covers:

- Startup readiness: Jenkins starts from the staged WAR and writes runtime logs.
- Endpoint reachability: HTTP checks reach the running Jenkins controller.
- Artifact freshness: staged artifacts and rendered config are verified by
  manifest/checksum before mutation.
- LDAP access: the Jenkins controller target can open a TCP connection to the
  reviewed LDAP endpoint.
- Plugin readiness: every curated plugin from `JENKINS_PLUGIN_LIST` is
  installed from staged artifacts.
- JCasC readiness: LDAP realm exists and the built-in node has zero executors.
- Gerrit SSH connectivity: the controller can open a TCP connection to the
  reviewed Gerrit SSH endpoint.
- Gerrit Trigger readiness: server config references the integration account
  and reviewed credential ID.
- Agent readiness: successful `validate-agent` evidence comes from real
  controller-to-agent scheduling.
- Trigger voting readiness: successful `verify-trigger` evidence comes from
  real Gerrit event, Jenkins build, agent execution, and `Verified +1`
  verification.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> validate
```

Harness gate:

```bash
simulation/docker/docker-harness.sh run-role-gate --role jenkins-controller
```

## Phase 13: Evidence Collection

Consumed inputs:

- Reviewed Jenkins controller env values.
- Staged artifact manifest and checksums.
- Jenkins home readiness files.
- Step 8 modeled agent scheduling and trigger-vote records.
- Real agent scheduling and trigger-vote evidence from the Step 11
  runtime-capable Docker simulation.
- Public key files for fingerprinting.
- Bounded log directory.

Produced outputs:

- Role-local Jenkins controller evidence JSON under `JENKINS_EVIDENCE_DIR`.
- A helper bounded log file under `JENKINS_LOG_DIR`.
- In the shared Docker harness, canonical evidence under
  `simulation/evidence/docker/harness/<run-id>/`.
- For Step 8 compatibility, the harness also mirrors evidence to ignored
  `simulation/docker/state/evidence/`.

Evidence Contract fields:

- Verification mode.
- Timestamp.
- Role or environment name.
- Checkpoint name.
- Command name.
- Status.
- Reviewed input fingerprint.
- Artifact manifest references.
- Checksum references and verification result.
- Observed checks.
- Bounded log references.
- Redaction status.

`collect-evidence` is fail-closed. In Step 8 it emits passing evidence only
when real runtime proof records are present and explicitly tied to the
reviewed run ID, staged artifacts, and bounded logs. The evidence
must state that real Jenkins/Gerrit/agent end-to-end execution is deferred to
Step 11.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> collect-evidence
```

Evidence must not expose private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Verbose Jenkins, Gerrit, Docker,
package-manager, SSH, VM, or verification logs must be referenced as bounded
log files rather than streamed.
