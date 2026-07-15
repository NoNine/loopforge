# Jenkins Controller Setup Manual

This manual owns the Jenkins controller reviewed-input helper workflow. The
helper `scripts/jenkins-controller-setup.sh` is a repeatable accelerator for
reviewed env files; it does not replace operator review or the direct
procedure in `docs/operations/native/jenkins-controller.md`.

`docs/contracts/lifecycle-contract.md` owns shared phase behavior, checkpoint semantics,
mutation boundaries, and resume/rerun rules. This manual owns only the Jenkins
controller-specific application of that contract.

The native reference is the procedural baseline for direct OS and Jenkins
controller operations. Keep this helper workflow aligned with that baseline
and preserve equivalent product state and validation outcomes. The native
reference must remain free of repository helper commands.

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

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, Jenkins controller
`2.555.3 LTS`, and Jenkins Plugin Installation Manager Tool `2.15.0`.
`docs/baselines/version-baseline.md` owns the package-wide baseline and reviewed update
rules.

## Phase 1: Operator Inputs

Consumed inputs:

- `examples/jenkins-controller.env.example` copied to a reviewed local env
  file.
- Jenkins URL, host, HTTP port, runtime account, runtime group, and Jenkins
  home path.
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
- `JENKINS_OS_DEPENDENCIES`, whose baseline and layered package rationale are
  defined in `docs/baselines/package-requirements.md`.

Deferred integration inputs:

- Jenkins-to-Gerrit credential file locations and public key delivery paths.
- Jenkins-to-agent credential file locations and public key delivery paths.
- Shared Jenkins controller/agent group and storage values from
  `examples/integration.env.example`.
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
- Target host baseline from `docs/baselines/version-baseline.md`, approved internal
  Ubuntu/OS package repositories, and reachable LDAP.
- Gerrit and Jenkins agent endpoint values as inventory for deferred later
  shared-integration inventory values only; Step 8 preflight does not require
  Gerrit or agent SSH reachability.
- Jenkins OS dependency expectations defined in
  `docs/baselines/package-requirements.md`.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline
  values, controller endpoint values, LDAP assumptions, deferred integration
  inventory values, and artifact paths.
- OS dependency expectation checks for the package/tooling names above.
- Runtime identity readiness: fully absent account/group/product-home state is
  accepted for creation by `install`, fully matching state is accepted for
  reuse, and partial or conflicting state blocks.

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

## Phase 3: Jenkins Direct Plugin Pin Review

Direct plugin pin review is an operator input step, not a helper-generated
proposal workflow. Operators review and record `JENKINS_PLUGIN_LIST` in the
reviewed Jenkins controller env file as direct `plugin-name:version` pins.
The list must contain exactly one accepted pin for each
`JENKINS_DIRECT_PLUGIN_NAMES` entry and must not include transitive
dependencies.

## Phase 4: Curated Jenkins Controller Artifact And Plugin Preparation

Artifact preparation runs in the bundle factory environment, not on the
Jenkins controller target. The shared Docker harness runs this phase in the
bundle factory container for Step 8 validation.

Jenkins Web UI plugin installation does not run the standalone
`jenkins-plugin-manager-*.jar`. The Web UI uses Jenkins core PluginManager and
UpdateCenter behavior, installing missing dependencies and upgrading installed
dependencies older than required versions. The Plugin Installation Manager CLI
remains the official pre-start automation tool for preparing artifacts from
Update Center metadata, but artifact preparation must use its
latest-compatible dependency behavior rather than `--latest false` minimum
dependency mode.

Consumed inputs:

- Reviewed Jenkins controller env values.
- Version baseline: Jenkins 2.555.3 LTS, OpenJDK 21, Jenkins Plugin
  Installation Manager Tool 2.15.0, Ubuntu release `24.04`, codename `noble`.
- Accepted direct Jenkins plugin pins from `JENKINS_PLUGIN_LIST`.
- Plugin Installation Manager is used here to resolve and download the
  latest-compatible full plugin closure from accepted direct pins. The helper
  verifies every direct pin remains at the exact accepted version.
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
- Controller-only JCasC and service templates.
- No Jenkins credentials, Gerrit Trigger server, agent-node, disposable
  verification job, or trigger-verification env templates are staged by the
  controller role helper. Those cross-role artifacts belong to the later
  shared integration workflow.
- `manifest.txt` records only compact artifact identity and inventory fields.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `JENKINS_ARTIFACT_OUTPUT_DIR` |
| Bundle-factory workspace | `/var/lib/loopforge/preparing/jenkins-artifacts-bundle/jenkins` |
| Docker harness exported output | `generated/simulation/docker/<run-id>/target/artifacts/exported/jenkins-artifacts-bundle.tar.gz` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- In Docker simulation, successful preparation exports the bundle to the
  `target/artifacts/exported/jenkins-artifacts-bundle.tar.gz` handoff path.
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
simulation/docker/simulate.sh prepare-artifacts --role jenkins-controller
```

## Phase 5: Jenkins Installation

Installation consumes only staged bundle factory output. The target verifies
`manifest.txt` and `checksums.sha256` before mutation.

Consumed inputs:

- Reviewed Jenkins controller env file.
- Extracted artifact payload root, normally `/var/lib/loopforge/staging/jenkins`
  in Docker simulation and target deployment.
- `manifest.txt` and `checksums.sha256`.

Produced outputs:

- Jenkins home tree under `JENKINS_HOME`.
- `war/jenkins.war`.
- `war/jenkins-plugin-manager.jar`.
- Staged templates under `templates/`.
- Install marker under `state/install.status`.

Mutation side effects:

- Creates the reviewed Jenkins primary group, runtime account, and
  `/var/lib/jenkins` product home when all three are absent, or reuses the
  fully matching set. It does not repair partial or mismatched state.
- Creates or updates Jenkins role-local home files.
- Uses `JENKINS_RUNTIME_GROUP`, defaulting to `jenkins`, for role-local
  Jenkins home ownership.
- Does not download Jenkins application artifacts on the target.
- Does not create the shared Jenkins integration group or shared storage path;
  those are owned by `scripts/integration-setup.sh` with
  `examples/integration.env.example`.

Helper:

```bash
scripts/jenkins-controller-setup.sh --env <reviewed-jenkins.env> --yes install
```

## Phase 6: Jenkins Runtime Configuration

Consumed inputs:

- Reviewed Jenkins controller env file.
- Staged service template.
- Jenkins runtime account, runtime group, home path, HTTP port, and JCasC
  location.

Produced outputs:

- Rendered service environment file.
- Service configuration marker.
- Real Jenkins controller runtime configuration ready to start from the staged
  Jenkins WAR, plugin set, JCasC material, and reviewed HTTP port.

Mutation side effects:

- Creates or updates Jenkins role-local runtime service settings.
- Installs or updates the runtime lifecycle definition; Jenkins starts or
  restarts only after the plugin and JCasC configuration phases are complete.
- Uses guest systemd for VM simulation and target deployment. Docker retains
  its existing direct-process model.

Validation is observational: it checks an already-running Jenkins runtime and
must fail rather than start or repair it. The operator-interface parity rules
are defined in `docs/contracts/operator-execution-contract.md`.

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

Gerrit Trigger configuration is deferred to the shared integration step. Step 8
is Jenkins controller-only bringup and must not require Gerrit-side mutation,
Jenkins-to-Gerrit SSH proof, Gerrit event streaming, agent scheduling, or
`Verified` voting. Cross-role trigger configuration belongs to
`scripts/integration-setup.sh`.

After Gerrit, Jenkins controller, and Jenkins agent role manuals are complete,
use `docs/operations/native/integration.md` for manual
target-deployment integration operations. Use
`docs/operations/setup/integration.md` only for the shared helper workflow.

Controller-only setup must not create or rotate Jenkins-to-Gerrit or
Jenkins-to-agent keypairs, install public keys on Gerrit or the agent, register
controller nodes, configure Gerrit Trigger, create disposable verification
artifacts, or claim trigger/vote evidence. The shared integration workflow
keeps private keys on the Jenkins controller, uses SSH for Gerrit Trigger
authentication and `stream-events`, and uses the Gerrit REST review API as the
default `Verified` vote posting path.

Failure classification follows `docs/contracts/gerrit-trigger-integration.md`: SSH
credential failures, `stream-events` failures, job/agent scheduling failures,
REST vote failures, and Gerrit review-state failures must remain distinct.

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
  `JENKINS_PLUGIN_LIST` is installed from staged artifacts at the exact
  accepted version, and Jenkins startup log checks prevent plugin-load
  failures from passing validation.
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
simulation/docker/simulate.sh configure-role --role jenkins-controller
simulation/docker/simulate.sh validate-role --role jenkins-controller
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
  `generated/simulation/docker/<run-id>/target/evidence/jenkins-controller/`.

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
