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

Jenkins controller application artifact bundles are key-free. They may contain
reviewed templates, manifests, checksums, WAR files, plugin artifacts, and job
definitions, but they must not contain SSH private keys, public keys,
`authorized_keys`, or generated public-key handoff files. Jenkins-to-Gerrit
and Jenkins-to-agent keypair generation and public-key handoff are later
integration-step work.

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
- Artifact output path, staged artifact path, verification mode, evidence
  directory, and bounded log directory.
- `JENKINS_DIRECT_PLUGIN_NAMES`, with operator-owned direct plugin intent as
  plugin names only.
- `JENKINS_PLUGIN_LIST`, with accepted direct plugin pins as `name:version`
  entries. Do not add transitive dependencies to this env value only because
  they appear in Plugin Installation Manager resolver output.
- `JENKINS_OS_DEPENDENCIES`, which defaults to controller target OS package
  expectations from the approved Jenkins reference: `ca-certificates`, `curl`,
  `fontconfig`, `git`, `net-tools`, `netcat-openbsd`, `openjdk-21-jre`,
  `openssh-client`, `rsync`, `tar`, `unzip`, and `wget`.

Deferred integration inputs:

- Jenkins-to-Gerrit credential file locations and public key delivery paths.
- Jenkins-to-agent credential file locations and public key delivery paths.
- These values are not required for controller-only bringup and are consumed
  only by the shared integration helper.

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
  approved internal Ubuntu/OS package repositories, and reachable LDAP.
- Gerrit and Jenkins agent endpoint values as inventory for deferred later
  shared-integration inventory values only; Step 8 preflight does not require
  Gerrit or agent SSH reachability.
- Jenkins OS dependency expectations listed in Phase 1.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline
  values, controller endpoint values, LDAP assumptions, deferred integration
  inventory values, and artifact paths.
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

## Phase 3: Jenkins Direct Plugin Version Proposal

Plugin version proposal runs in the bundle factory environment, not on the
Jenkins controller target. The Jenkins Plugin Installation Manager Tool is the
authoritative resolver for this workflow.

Consumed inputs:

- Reviewed Jenkins controller env values.
- `JENKINS_DIRECT_PLUGIN_NAMES`, names only.
- The package v1 Jenkins baseline: Jenkins 2.555.3 LTS and Jenkins Plugin
  Installation Manager Tool 2.15.0.
- Reviewed Jenkins WAR and Plugin Installation Manager artifact source paths,
  or `JENKINS_DOWNLOAD_ARTIFACTS=1` in the bundle-factory Docker simulation
  path.

Produced outputs:

- `plugins.intent.txt`, generated from `JENKINS_DIRECT_PLUGIN_NAMES`.
- `plugin-version-proposals.txt`, containing only direct
  `plugin-name:version` proposals.
- `plugin-version-resolution-report.txt`, preserving the full Plugin
  Installation Manager resolver output as evidence.

Acceptance:

- Review the proposal and full resolver report.
- Accept explicitly with `--write-env --yes`; this updates only
  `JENKINS_PLUGIN_LIST` in the reviewed env file.
- `JENKINS_PLUGIN_LIST` remains limited to direct plugin pins. Transitive
  dependencies are captured later in `plugins.lock.txt`.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> propose-plugin-versions
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --write-env --yes propose-plugin-versions
```

## Phase 4: Curated Jenkins Controller Artifact And Plugin Preparation

Artifact preparation runs in the bundle factory environment, not on the
Jenkins controller target. The shared Docker harness runs this phase in the
bundle factory container for Step 8 validation.

Consumed inputs:

- Reviewed Jenkins controller env values.
- Version baseline: Jenkins 2.555.3 LTS, OpenJDK 21, Jenkins Plugin
  Installation Manager Tool 2.15.0, Ubuntu release `24.04`, codename `noble`.
- Accepted direct Jenkins plugin pins from `JENKINS_PLUGIN_LIST`.
- Reviewed controller artifact source paths, or `JENKINS_DOWNLOAD_ARTIFACTS=1`
  in the bundle-factory Docker simulation path. Any public internet use here
  is labeled `simulation-only` and remains outside target-host application
  artifact installation.
- Jenkins controller templates under `templates/jenkins-controller/`.

Produced outputs:

- `manifest.txt`.
- `checksums.sha256`.
- Curated Jenkins WAR artifact for real controller startup.
- Curated Jenkins Plugin Installation Manager Tool artifact.
- Curated Jenkins plugin artifacts, including resolved dependency plugins,
  staged from reviewed sources or resolved in the bundle factory.
- `plugins.seed.txt`, generated from accepted direct pins as internal Plugin
  Installation Manager input.
- `plugins.lock.txt`, generated from downloaded plugin manifests as the full
  direct-plus-transitive closure.
- Plugin artifact manifest, plugin resolution report, and plugin review
  report.
- Controller-only JCasC and service templates.
- No Jenkins credentials, Gerrit Trigger server, agent-node, disposable
  verification job, or trigger-verification env templates are staged by the
  controller role helper. Those cross-role artifacts belong to the later
  shared integration workflow.
- `manifest.txt` records `artifact_source=curated-bundle-factory`,
  `os_dependency_source=approved-internal-os-repos`,
  `public_internet_fallback=simulation-only`, and `bundle_contains_keys=no`.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `JENKINS_ARTIFACT_OUTPUT_DIR` |
| Docker harness bundle output | `/harness/state/artifacts/jenkins-controller` inside the bundle factory |
| Docker harness host state | `simulation/state/docker/harness/<run-id>/bundle-factory/artifacts/jenkins-controller/` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- Does not install, configure, or start Jenkins.
- Does not write SSH private keys, public keys, `authorized_keys`, or
  generated key handoff files into the artifact bundle. Artifact preparation
  fails if key material is detected.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> prepare-artifacts
```

Harness:

```bash
simulation/docker/docker-harness.sh prepare-artifacts --role jenkins-controller
```

## Phase 5: Jenkins Installation

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

## Phase 6: Jenkins Runtime Configuration

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

## Phase 7: LDAP/JCasC Configuration

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

## Phase 8: Shared Gerrit Trigger Integration Handoff

Gerrit Trigger configuration is deferred to the later integration step. Step 8
is Jenkins controller-only bringup and must not require Gerrit-side mutation,
Jenkins-to-Gerrit SSH proof, Gerrit event streaming, agent scheduling, or
`Verified` voting. Cross-role trigger configuration belongs to
`scripts/integration-setup.sh`.

Consumed inputs:

- Jenkins Gerrit integration account.
- Jenkins Gerrit credential ID.
- Gerrit HTTP URL, SSH host, SSH port, and Gerrit Trigger server name.
- Staged credentials and Gerrit Trigger templates.
- Jenkins-to-Gerrit private key and public key for the later integration
  workflow.

Later integration-step outputs, not Step 8 accepted outputs:

- Rendered Jenkins credentials material referencing the credential IDs.
- Rendered Gerrit Trigger server configuration.
- Gerrit Trigger readiness marker.

Deferred mutation side effects:

- Creates or updates Jenkins credential and Gerrit Trigger config through the
  shared integration helper in the later integration step.
- Does not write private key material into evidence.

Later shared helper:

```bash
scripts/integration-setup.sh \
  --gerrit-env <reviewed-gerrit.env> \
  --jenkins-controller-env <reviewed-jenkins-controller.env> \
  --jenkins-agent-env <reviewed-jenkins-agent.env> \
  configure-trigger
```

## Phase 9: Deferred Jenkins-To-Gerrit SSH Key Handoff

Jenkins-to-Gerrit key generation is deferred to the later integration step.
Controller-only validation must not require this credential material.

Consumed inputs:

- Reviewed controller-owned credential path.
- Public key delivery path for Gerrit.
- Jenkins Gerrit integration account name.

Later integration-step outputs, not Step 8 accepted outputs:

- Jenkins-to-Gerrit private key owned by the Jenkins controller workflow.
- Jenkins-to-Gerrit public key delivery file for Gerrit.
- Public key fingerprint in status and evidence.

Key handoff:

- Jenkins controller retains the private key.
- Gerrit consumes only the public key through the shared integration workflow.

Deferred mutation side effects:

- Creates or rotates the controller-held Jenkins-to-Gerrit keypair in the later
  integration step.

Later shared helper:

```bash
scripts/integration-setup.sh \
  --gerrit-env <reviewed-gerrit.env> \
  --jenkins-controller-env <reviewed-jenkins-controller.env> \
  --jenkins-agent-env <reviewed-jenkins-agent.env> \
  configure-gerrit-ssh
```

## Phase 10: Deferred Build-Agent SSH Key Handoff

Jenkins-to-agent key generation is deferred to the later integration step.
Step 8 controller-only validation must not require a configured build agent.

Consumed inputs:

- Reviewed controller-owned agent credential path.
- Public key transfer path for the Jenkins agent host.
- Jenkins agent account name.

Later integration-step outputs, not Step 8 accepted outputs:

- Jenkins-to-agent private key owned by the Jenkins controller workflow.
- Public key transfer file for the later agent integration workflow.
- Public key fingerprint in status and evidence.

Key handoff:

- Jenkins controller retains the private key.
- Jenkins agent consumes only the public key through the shared integration
  workflow.

Deferred mutation side effects:

- Creates or rotates the controller-held Jenkins-to-agent keypair in the later
  integration step.

Later shared helper:

```bash
scripts/integration-setup.sh \
  --gerrit-env <reviewed-gerrit.env> \
  --jenkins-controller-env <reviewed-jenkins-controller.env> \
  --jenkins-agent-env <reviewed-jenkins-agent.env> \
  configure-agent-ssh
```

## Phase 11: Deferred Build-Agent Registration And Scheduling Validation

Build-agent registration and scheduling validation are deferred to the later
integration step, after Jenkins controller and Jenkins agent host-only bringup
are both accepted.

Consumed inputs:

- Jenkins agent host, SSH port, runtime account, node name, scheduling labels,
  remote filesystem, executor count, and credential ID.
- Controller-held Jenkins-to-agent private key.
- Public key delivery path for the agent host.
- Staged agent-node template.

Later integration-step outputs, not Step 8 accepted outputs:

- Rendered Jenkins agent node config.
- Agent registration marker.
- Jenkins controller-side node registration state.
- Shared `validate-integration` must require `--yes` for mutation and must
  either run a real Jenkins runtime node/smoke proof against the configured
  SSH agent or exit nonzero with a clear blocked or unsupported status.

Deferred mutation side effects:

- Creates or updates Jenkins node configuration through the shared integration
  helper in the later integration step.
- `validate-integration --dry-run` must not create Gerrit or Jenkins state.
  Non-dry-run validation must not pass with a modeled scheduling record when
  the later integration step runs. The agent helper owns only host-side SSH
  readiness.

Later shared helper:

```bash
scripts/integration-setup.sh \
  --gerrit-env <reviewed-gerrit.env> \
  --jenkins-controller-env <reviewed-jenkins-controller.env> \
  --jenkins-agent-env <reviewed-jenkins-agent.env> \
  --yes validate-integration
```

## Phase 12: Deferred End-To-End Gerrit Trigger Verification

End-to-end Gerrit Trigger verification is deferred to the later integration
step. Step 8 controller-only validation must not claim patchset-created event
streaming, agent execution, or `Verified` vote proof.

Consumed inputs:

- Gerrit Trigger server configuration.
- Later integration-step agent scheduling evidence.
- Disposable Gerrit project, branch, and verification run ID.
- Disposable verification job template.

Later integration-step outputs, not Step 8 accepted outputs:

- Disposable verification job config and trigger inputs.
- Gerrit Trigger verification evidence from real Jenkins/Gerrit interaction,
  or a nonzero blocked/unsupported result when the real interaction cannot run.

Deferred mutation side effects:

- Creates disposable verification templates and records the real verification
  result for the reviewed run ID in the later integration step.
- Docker harness mode must not pass with modeled `patchset-created`, agent
  build, or `Verified +1` voting. If the role gate cannot complete the real
  verification at this step, it must fail or report blocked. Step 11 remains
  the full cross-role Docker gate that aggregates the same real workflow across
  all five environments.

Later shared helper:

```bash
scripts/integration-setup.sh \
  --gerrit-env <reviewed-gerrit.env> \
  --jenkins-controller-env <reviewed-jenkins-controller.env> \
  --jenkins-agent-env <reviewed-jenkins-agent.env> \
  --yes verify-trigger
```

Failure classification follows `docs/gerrit-trigger-integration.md`: SSH
credential failures, `stream-events` failures, job/agent scheduling failures,
and `Verified` voting failures must remain distinct.

## Phase 13: Validation

Validation in Step 8 proves Jenkins controller-only readiness with real runtime
checks for controller lifecycle phases. It verifies staged artifacts, rendered
configuration, accepted direct plugin pins and resolved plugin closure,
LDAP/JCasC configuration, LDAP reachability, Jenkins controller startup,
endpoint reachability, bounded logs, and evidence.
Gerrit SSH reachability, Gerrit Trigger readiness, agent scheduling, and
trigger voting are deferred to the later shared integration step.

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
- Plugin readiness: every accepted direct plugin pin from
  `JENKINS_PLUGIN_LIST` is installed from staged artifacts, and the full
  direct-plus-transitive closure is retained in `plugins.lock.txt`.
- JCasC readiness: LDAP realm exists and the built-in node has zero executors.
- Gerrit SSH connectivity: deferred to the later integration step.
- Gerrit Trigger readiness: deferred to the later integration step.
- Agent readiness: deferred to the later integration step.
- Trigger voting readiness: deferred to the later integration step.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> validate
```

Harness gate:

```bash
simulation/docker/docker-harness.sh run-role-gate --role jenkins-controller
```

## Phase 14: Evidence Collection

Consumed inputs:

- Reviewed Jenkins controller env values.
- Staged artifact manifest and checksums.
- Jenkins home readiness files.
- Controller-only readiness state.
- Integration evidence is produced by the shared integration helper, not by the
  controller role helper.
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
when real controller runtime proof records are present and explicitly tied to
the reviewed run ID, staged artifacts, and bounded logs. The evidence must
state that real Jenkins/Gerrit/agent end-to-end execution is deferred to the
later integration step and records no private keys, tokens, passwords, or LDAP
bind secrets.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> collect-evidence
```

Evidence must not expose private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Verbose Jenkins, Gerrit, Docker,
package-manager, SSH, VM, or verification logs must be referenced as bounded
log files rather than streamed.
