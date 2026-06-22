# Jenkins Agent Setup Manual

This manual is the authority for the Jenkins SSH build-agent host role. The
helper `scripts/jenkins-agent-setup.sh` is a repeatable accelerator for
reviewed env files; it does not replace operator review.

Maintain this manual with `docs/jenkins-agent-native-operations-reference.md`.
The native reference is the strong reference for direct OS, OpenSSH, and
Jenkins agent operations and must remain free of repository helper commands.

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

Default baseline:

| Item | Default |
| --- | --- |
| Ubuntu target | 24.04.4 LTS, release `24.04`, codename `noble` |
| Java | OpenJDK 21 |
| Agent SSH tooling | OpenSSH server and client |
| Jenkins plugin dependency | Jenkins SSH Build Agents plugin from the controller plugin bundle |

## Phase 1: Operator Inputs

Consumed inputs:

- `examples/jenkins-agent.env.example` copied to a reviewed local env file.
- Agent host, SSH port, dedicated runtime account, runtime group, remote
  filesystem path, Jenkins node name, Jenkins scheduling labels, staged
  artifact path, artifact output path, verification mode, evidence directory,
  and bounded log directory.
- `JENKINS_AGENT_OS_DEPENDENCIES`, which defaults to the static agent target
  OS package baseline from the approved agent reference adapted to v1:
  `ca-certificates`, `curl`, `git`, `openssh-client`, `openssh-server`,
  `openjdk-21-jre`, `rsync`, `tar`, `unzip`, and `wget`.

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
- Target host baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21 expectation,
  OpenSSH server/client tooling, approved internal Ubuntu/OS package
  repositories, and agent host inventory values.
- Jenkins controller-side assumption that the SSH Build Agents plugin is in
  the curated controller plugin bundle.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline
  values, SSH endpoint values, runtime account values, remote filesystem
  path, node name, labels, and artifact paths.
- OS dependency expectation checks for the package/tooling names above.

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
- Package intent manifest describing the static OS package baseline without
  creating an Ubuntu dependency bundle.
- Runtime profile and SSH daemon policy templates.
- Explicit bundle metadata proving the bundle contains no SSH key material.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `JENKINS_AGENT_ARTIFACT_OUTPUT_DIR` |
| Docker harness bundle output | `/harness/state/artifacts/jenkins-agent` inside the bundle factory |
| Docker harness host state | `simulation/state/docker/<run-id>/bundle-factory/artifacts/jenkins-agent/` |

Side effects:

- Writes artifact files only in the bundle factory output path.
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
- Staged artifact directory, normally `/harness/staged` in the Docker role
  gate.
- `manifest.txt` and `checksums.sha256`.

Produced outputs:

- Agent state tree under `JENKINS_AGENT_STATE_DIR`.
- Installed bootstrap marker.
- Installed package intent manifest.
- Installed templates.
- `artifact-manifest.txt` and `artifact-checksums.sha256`.
- Install marker under `state/install.status`.

Mutation side effects:

- Creates or updates role-local agent state files.
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

The helper requires the configured local runtime account and group to already
exist. It fails clearly when either is missing, or when the existing account
passwd HOME is not `/var/lib/jenkins-agent`. Native account and group
provisioning is outside the helper.

Consumed inputs:

- Reviewed Jenkins agent env file.
- Staged artifact manifest and checksums.
- Dedicated runtime account name, runtime group, and remote filesystem path.

Produced outputs:

- Runtime filesystem at `JENKINS_AGENT_REMOTE_FS`.
- Runtime profile rendered from the staged template.
- SSH daemon policy rendered from the staged template.
- Runtime readiness marker under `state/runtime.status`.

Mutation side effects:

- Verifies the dedicated local runtime account and role-local runtime group
  from `JENKINS_AGENT_GROUP`, defaulting to `jenkins-agent`.
- Creates or updates the remote filesystem.
- Starts OpenSSH `sshd` in the Docker harness target so Step 9 can prove real
  SSH reachability without claiming Jenkins controller scheduling.
- Leaves `authorized_keys` creation and Jenkins public-key installation to the
  later shared integration workflow.
- Leaves the shared Jenkins integration group and shared storage path to
  `scripts/integration-setup.sh` with `examples/integration.env.example`.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> --yes configure-runtime
```

Later integration key rules:

- Jenkins-to-agent keypair generation and public-key transfer are performed
  only during the later shared integration workflow.
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
- Staged manifest and checksums.
- Runtime account, runtime group, remote filesystem, and SSH readiness state.

Produced outputs:

- Validation result for SSH reachability, remote filesystem readiness, runtime
  account ownership, staged artifact checks, and bounded logs.
- Role-local evidence from `collect-evidence`.

Validation checks:

- The OpenSSH banner is reachable at
  `JENKINS_AGENT_HOST:JENKINS_AGENT_SSH_PORT` in the Docker harness.
- The dedicated runtime account exists.
- `JENKINS_AGENT_REMOTE_FS` exists and is owned by the runtime account and
  role-local runtime group.
- Staged artifact checksums still verify before readiness is reported.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> validate
```

Jenkins controller scope:

- Jenkins controller node registration, credential selection, label/executor
  policy, controller-to-agent scheduling, and later integration validation
  jobs are deferred to `scripts/integration-setup.sh`.
- Step 9 proves only agent host-side readiness: SSH daemon reachability,
  runtime account ownership, remote filesystem readiness, staged artifact
  checks, bounded logs, and evidence.
- Real cross-role trigger execution and `Verified` voting are aggregated by
  the later shared integration step after role helpers are compliant.
- After Gerrit, Jenkins controller, and Jenkins agent role manuals are
  complete, use `docs/integration-setup-manual.md` for the shared
  `scripts/integration-setup.sh` workflow. The agent manual remains limited to
  agent host readiness and does not duplicate the cross-role command sequence.

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
- Role name and checkpoint.
- Command name.
- Pass/fail status.
- Reviewed input fingerprint.
- Artifact manifest and checksum references.
- Checksum verification result.
- SSH reachability.
- Runtime account ownership.
- Remote filesystem readiness.
- Jenkins agent label and executor context as controller-owned metadata only.
- Bounded log references.
- Redaction status.

Helper:

```bash
scripts/jenkins-agent-setup.sh --env <reviewed-agent.env> collect-evidence
```

The evidence must not include private keys, tokens, passwords, LDAP bind
secrets, or full secret-bearing env values.
