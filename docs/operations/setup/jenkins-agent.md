# Jenkins Agent Setup Manual

This manual owns the Jenkins SSH build-agent host reviewed-input helper
workflow. The helper `scripts/jenkins-agent-setup.sh` is a repeatable
accelerator for reviewed env files; it does not replace operator review or the
direct procedure in `docs/operations/native/jenkins-agent.md`.

`docs/contracts/lifecycle-contract.md` owns shared phase behavior, product
checkpoint semantics, mutation boundaries, and resume/rerun rules. This manual
owns only the Jenkins agent-specific application of that contract.

The native reference is the procedural baseline for direct OS, OpenSSH, and
Jenkins agent operations. Keep this helper workflow aligned with that baseline
and preserve equivalent product state and validation outcomes. The native
reference must remain free of repository helper commands.

The v1 boundary is unchanged: agent bootstrap artifacts, templates, manifests,
and checksums are prepared in the bundle factory, staged to the Jenkins agent
target, and verified by manifest and checksum before target mutation.
Application artifacts and SSH credential material are separate from OS
dependencies. Jenkins agent application/bootstrap artifacts must not include
Gerrit, Jenkins, or agent SSH key material. Target-host Ubuntu/OS dependencies
are installed only from approved internal OS repositories in target-deployment
use. Public internet fallback for target-host Ubuntu/OS dependency installation
is simulation-only and must be labeled that way in docs, logs, and evidence.

Jenkins connects out to the agent over SSH. The agent helper owns only the
agent host side: OS/tooling readiness, runtime account readiness, remote
filesystem readiness, SSH daemon reachability, staged artifact checks, bounded
logs, and evidence. It must not update `authorized_keys`, register a Jenkins
node, prove Jenkins scheduling, configure Gerrit Trigger, or prove `Verified`
voting. Jenkins controller node registration, credential storage, executor
count, label assignment, and scheduling validation remain in the later
integration step.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, OpenSSH
server/client tooling, and the Jenkins SSH Build Agents plugin from the
controller plugin bundle. `docs/baselines/version-baseline.md` owns the package-wide
baseline and reviewed update rules.

## Phase 1: Operator Inputs

Consumed inputs:

- `examples/jenkins-agent.env.example` copied to a reviewed local env file.
- Agent host, SSH port, dedicated runtime account, runtime group, remote
  filesystem path, Jenkins node name, Jenkins scheduling labels, staged
  artifact path, artifact output path, verification mode, evidence directory,
  and bounded log directory.
- `JENKINS_AGENT_OS_DEPENDENCIES`, whose baseline and layered package rationale
  are defined in `docs/baselines/package-requirements.md`.

Produced outputs:

- Reviewed Jenkins agent env file.
- Sanitized input fingerprint in evidence.

Side effects:

- Local env-file review only. No agent target mutation.

Helper:

```bash
scripts/jenkins-agent-setup.sh print-env-template
```

Secret-redaction expectations:

- Evidence must not record private keys, passwords, tokens, LDAP bind secrets,
  or full secret-bearing env values.
- Evidence may record account names, node names, labels, endpoints, remote
  filesystem paths, manifest paths, checksum paths, and bounded log
  references.

## Phase 2: Prerequisite Readiness

Consumed inputs:

- Reviewed Jenkins agent env file.
- Target host baseline from `docs/baselines/version-baseline.md`, approved internal
  Ubuntu/OS package repositories, and agent host inventory values.
- Jenkins controller-side assumption that the SSH Build Agents plugin is in
  the curated controller plugin bundle.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline
  values, SSH endpoint values, runtime account values, remote filesystem
  path, node name, labels, and artifact paths.
- OS dependency expectation checks for the package/tooling names above.
- Runtime identity readiness: fully absent account/group/product-home state is
  accepted for creation by `install`; a fully matching identity with an empty
  product home is accepted for adoption. Other existing application state,
  partial state, or conflicting state blocks unless an exact input-bound
  completion record returns non-mutating `already-complete`.

Side effects:

- None. Preflight is non-mutating.
- The helper does not provide offline Ubuntu dependency bundle commands.
  Target hosts may use approved internal Ubuntu/OS package repositories.
  Public internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only and must be labeled in docs, logs, and evidence.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> preflight
```

For dry-run review:

```bash
scripts/jenkins-agent-setup.sh --env examples/jenkins-agent.env.example --dry-run preflight
```

## Phase 3: Curated Agent Artifact Preparation

Artifact preparation runs in the bundle factory environment, not on the
Jenkins agent target. The shared Docker harness runs this phase in the bundle
factory container for Step 9 validation.

Consumed inputs:

- Reviewed Jenkins agent env values.
- Version baseline: OpenJDK 21, Ubuntu release `24.04`, codename `noble`.
- Jenkins agent templates under `templates/jenkins-agent/`.

Produced outputs:

- `manifest.txt`.
- `checksums.sha256`.
- Agent bootstrap marker for the Docker harness role gate.
- Runtime profile and SSH daemon policy templates.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `JENKINS_AGENT_ARTIFACT_OUTPUT_DIR` |
| Bundle-factory workspace | `/var/lib/loopforge/preparing/jenkins-agent-artifacts-bundle/jenkins-agent` |
| Docker harness exported output | `generated/simulation/docker/<run-id>/target/artifacts/exported/jenkins-agent-artifacts-bundle.tar.gz` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- In Docker simulation, successful preparation exports the bundle to the
  `target/artifacts/exported/jenkins-agent-artifacts-bundle.tar.gz` handoff path.
- Does not write private keys, public keys, `authorized_keys`, or other SSH
  credential material to the artifact bundle.
- Does not install packages, configure SSH, create accounts, or register a
  Jenkins node.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> prepare-artifacts
```

Harness:

```bash
simulation/docker/simulate.sh prepare-artifacts --role jenkins-agent
```

## Phase 4: Agent Host Installation

Installation consumes only staged bundle factory output. The target verifies
`manifest.txt` and `checksums.sha256` before mutation.

Consumed inputs:

- Reviewed Jenkins agent env file.
- Extracted artifact payload root, normally
  `/var/lib/loopforge/staging/jenkins-agent` in Docker simulation and target
  deployment.
- `manifest.txt` and `checksums.sha256`.

Produced outputs:

- Agent state tree under `JENKINS_AGENT_STATE_DIR`.
- Installed bootstrap marker.
- Installed templates.
- Install marker under `state/install.status`.

Mutation side effects:

- Resets helper-managed children under `JENKINS_AGENT_STATE_DIR` before
  installing staged output: `bootstrap/`, `templates/`, `state/`, `etc/`,
  `run/`, and `logs/`.
- Preserves the configured `JENKINS_AGENT_STATE_DIR` and
  `JENKINS_AGENT_REMOTE_FS` roots.
- Does not download Jenkins application artifacts on the target.
- Does not register a Jenkins node or claim executor scheduling.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> --yes install
```

## Phase 5: Agent Runtime Account And SSH Daemon Setup

Runtime configuration verifies staged artifacts again before mutation. The
agent host setup does not consume controller key material and does not update
`authorized_keys`. Jenkins-to-agent keypair generation, public-key transfer,
and access authorization remain later integration work.

The helper creates the configured local runtime group, account, and
`/var/lib/jenkins-agent` product home during `install` when the complete set is
absent. It may adopt a fully matching identity with an empty product home and
fails clearly on existing application state, partial state, numeric collisions,
a mismatched passwd HOME or primary group, or mismatched product-home
ownership. Exact input-bound completed state returns `already-complete` without
mutation.

Consumed inputs:

- Reviewed Jenkins agent env file.
- Staged artifact manifest and checksums.
- Dedicated runtime account name, runtime group, and remote filesystem path.

Produced outputs:

- Runtime filesystem at `JENKINS_AGENT_REMOTE_FS`.
- Runtime profile rendered from the staged template.
- Account-scoped SSH policy rendered from the staged template and installed as
  `/etc/ssh/sshd_config.d/40-jenkins-agent.conf` with `root:root 0644`
  custody.
- Runtime readiness marker under `state/runtime.status`.

Mutation side effects:

- Creates or verifies the dedicated local runtime account and role-local
  runtime group from the reviewed UID/GID values and
  `JENKINS_AGENT_GROUP`, defaulting to `jenkins-agent`.
- Creates the remote filesystem with reviewed ownership when the complete
  runtime identity state is absent; it does not repair existing mismatches.
- Requires the reviewed `JENKINS_AGENT_SSH_PORT` to exist in effective
  site-owned OpenSSH configuration before installing the role policy. The
  helper does not add `Port`, `ListenAddress`, or `AllowUsers` directives.
- Installs a `Match User` policy that requires public-key authentication and
  disables password, keyboard-interactive, and empty-password authentication
  for the agent account only.
- Runs `sshd -t` and account-specific `sshd -T -C` checks before service
  mutation. Invalid or ineffective policy blocks without reloading SSH.
- Enables, starts, and reloads the existing guest SSH service in VM simulation
  and target deployment. The agent remains an outbound SSH node and does not
  need a separate Jenkins agent daemon.
- Leaves `authorized_keys` creation and Jenkins public-key installation to
  integration-native operations or the shared helper workflow.
- Leaves the shared Jenkins integration group and shared storage path to
  `scripts/integration-setup.sh` with `examples/integration.env.example`.

Docker simulation validates the same effective account policy and reloads its
existing root-owned `sshd` master process. It does not claim guest-OS systemd
or reboot behavior. Operator-interface parity rules are defined in
`docs/operations/README.md`.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> --yes configure-runtime
```

Later integration key rules:

- Jenkins-to-agent keypair generation and public-key transfer are performed
  only during integration-native operations or the shared helper workflow.
- The transferred public-key material must be exactly one OpenSSH public-key
  line.
- Private key, PEM block, token, and password material are rejected by the
  integration workflow.
- Integration evidence may include the public key fingerprint, never
  private-key content.

## Phase 6: Agent Host Validation

Agent validation proves real agent-host-side readiness only. It does not prove
Jenkins controller scheduling, build execution, Gerrit Trigger events, or a
`Verified` vote.

Consumed inputs:

- Reviewed Jenkins agent env file.
- Successful install and runtime status records.
- Current Java, SSH service, and reviewed endpoint state.

Produced outputs:

- Validation result for OpenJDK 21, SSH service or Docker daemon state, SSH
  endpoint reachability, prior setup results, and bounded logs.
- Role-local evidence from `collect-evidence`.

Validation checks:

- The OS-managed SSH service has a valid `sshd` process in VM simulation, or
  the Docker target has a root-owned `sshd` daemon process.
- The OpenSSH banner is reachable at
  `JENKINS_AGENT_HOST:JENKINS_AGENT_SSH_PORT` in the selected harness.
- Java reports OpenJDK 21.
- The install status record captures successful staged-artifact verification.
- The runtime status record captures the canonical effective public-key-only
  SSH policy and successful service configuration.
- Validation does not repeat artifact checksum, runtime identity, filesystem,
  account shadow, or effective-policy setup checks.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> validate
```

Jenkins controller scope:

- Jenkins controller node registration, credential selection, label/executor
  policy, controller-to-agent scheduling, and later integration validation
  jobs are deferred to `scripts/integration-setup.sh`.
- Step 9 proves only agent host-side readiness: completed artifact, identity,
  filesystem, and policy setup results plus current Java, SSH service,
  endpoint, bounded-log, and evidence observations.
- Real cross-role trigger execution and `Verified` voting are aggregated by
  the later shared integration step after role helpers are compliant.
- After Gerrit, Jenkins controller, and Jenkins agent role manuals are
  complete, use `docs/operations/native/integration.md` for manual
  target-deployment integration operations. Use
  `docs/operations/setup/integration.md` only for the shared helper workflow. The
  agent manual remains limited to agent host readiness and does not duplicate
  the cross-role command sequence.

## Phase 7: Evidence Collection

Evidence collection follows the common Evidence Contract.

Consumed inputs:

- Reviewed Jenkins agent env file.
- Staged artifact manifest and checksums.
- Runtime account, remote filesystem, and SSH readiness state.
- Bounded validation logs.

Produced outputs:

- `jenkins-agent-readiness-<timestamp>.json` under
  `JENKINS_AGENT_EVIDENCE_DIR`.
- Bounded log under `JENKINS_AGENT_LOG_DIR`.

Observed checks recorded:

- Verification mode.
- Timestamp.
- Product checkpoint family and Jenkins agent role qualifier.
- Command name.
- Pass/fail status.
- Reviewed input fingerprint.
- Prior staged-artifact verification result and its manifest/checksum
  references.
- Prior effective account-policy and service-configuration result.
- OpenJDK 21, SSH service state, and SSH endpoint reachability.
- Jenkins agent label and executor context as controller-owned metadata only.
- Bounded log references.
- Redaction status.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> collect-evidence
```

The evidence must not include private keys, tokens, passwords, LDAP bind
secrets, or full secret-bearing env values.

The resulting evidence status is a producer outcome. In helper-assisted
`target-deployment`, a human must accept Jenkins agent role-local setup before
role-local validation and accept validation before integration in
`setup/acceptance-checklist.md`. In simulation, the harness accepts each
corresponding workflow checkpoint only after validating the record.
