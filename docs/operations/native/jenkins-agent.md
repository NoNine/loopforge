# Jenkins Agent Native Operations Reference

This document is the manual target-deployment native operations reference for
the Jenkins SSH build agent. It uses OS and application-native operations only,
not repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Agent application/bootstrap artifacts are prepared in the bundle-factory
environment and staged to the target before any mutation. Application artifacts
and SSH credential material are separate from OS dependencies: artifact bundles
must not include Gerrit, Jenkins, or agent SSH key material. Public internet
fallback for target-host Ubuntu/OS dependency installation is simulation-only
and must be labeled as such in docs, logs, and verification summaries.


Audience: production operators preparing a Jenkins outbound SSH build agent on
Ubuntu 24.04 LTS without Docker.

Use this manual with `docs/operations/native/jenkins-controller.md`. The
Jenkins controller manual covers controller installation and controller-only
configuration. Use `docs/operations/native/integration.md` after
agent-host readiness is proven. Controller-side node registration, Gerrit
integration, and Jenkins scheduling proof are later integration-step work. This
manual covers the build server baseline, agent application artifacts, SSH
access, recovery, and agent host-only validation.

Assumptions:

- Jenkins runs on its own Ubuntu 24.04 LTS host.
- The build agent runs on a separate Ubuntu 24.04 LTS host.
- Jenkins connects out to the build agent over SSH.
- The build agent exposes SSH only on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Jenkins agent application artifacts.
- Production host commands are run by the operator account with `sudo` or
  equivalent delegated administrator privileges unless noted. Do not use
  `root` as a Loopforge account or direct login identity.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, OpenSSH
server/client tooling, and the Jenkins SSH Build Agents plugin from the
controller plugin bundle. `docs/baselines/version-baseline.md` owns the package-wide
baseline and reviewed update rules.

Production warning: do not run builds on the Jenkins controller. Keep the
built-in node at zero executors and provide build capacity through agents.

Privilege warning: agent setup cannot be completed by an unprivileged user
alone. Package installation, local runtime accounts, SSH service control, and
remote filesystem ownership require delegated administrator privilege from
the operator account on the build server. Root may own OS-reserved files, but
root is not a Loopforge account, runtime identity, or supported direct login
identity.

Manual authority: this manual is the reference procedure. It intentionally
contains only native OS, OpenSSH, and Jenkins UI/application operations. Do not
add repository automation commands or automation-equivalent command tables to
this document.

## 1. Operator Inputs and Current Status

Record these values before installation:

| Item | Value |
| --- | --- |
| Agent host | `JENKINS_AGENT_HOST` |
| Agent SSH port | `22` or chosen port |
| Agent runtime user | `JENKINS_AGENT_ACCOUNT`, normally `jenkins-agent` |
| Agent remote FS | `JENKINS_AGENT_REMOTE_FS`, normally `/var/lib/jenkins-agent` |
| Jenkins node name | `JENKINS_AGENT_NODE_NAME`, normally `build-linux-x86-01` |
| Jenkins scheduling labels | `JENKINS_AGENT_LABELS`, normally `linux x86_64 general-build gerrit-ci` |
| Network mode | Approved internal OS repositories for target-host OS dependencies |

Run on the agent host:

```bash
getent hosts JENKINS_AGENT_HOST
hostnamectl
ip addr
df -h
free -h
java -version || true
systemctl --failed || true
```

### 1.1 If You Do Not Have Root Privileges

Use this manual as an administrator handoff. Without root on the build server,
you can prepare Jenkins agent application artifacts, collect host and SSH
values, review the controller node configuration, and run network checks
allowed by your account.

Ask an administrator to perform or delegate these build-server tasks:

- Install OS packages and Java dependencies.
- Confirm or create the local `jenkins-agent` runtime account and group.
- Create and own `/var/lib/jenkins-agent`.
- Enable and start `ssh` or `sshd`.
- Run any `apt`, `dpkg`, `systemctl`, `groupadd`, `useradd`, `chown`, `chmod`,
  or writes under system-owned paths.

## 2. Dependencies And Jenkins Agent Artifact Bundle

### 2.1 Ubuntu Dependency Setup

The package rationale and layered classification are maintained in
`docs/baselines/package-requirements.md`.

OS dependency setup also creates the dedicated `jenkins-agent` account and
enables SSH. It does not install Jenkins controller keys; controller credential
selection, node registration, and scheduling proof are later integration work.

Manual package baseline on the build server:

```bash
apt update
apt install -y \
  ca-certificates \
  curl \
  nfs-kernel-server \
  openjdk-21-jre-headless \
  openssh-server \
  rsync \
  tar \
  wget
java -version
```

Set `JENKINS_BUILD_EXTRA_PACKAGES` for site-wide packages needed on every
general build agent, such as `build-essential` when every agent needs a
compiler toolchain. Keep project-specific toolchains outside the default
baseline unless every general build agent needs them. Do not treat `sudo` as a
role dependency; it is an operator privilege mechanism.

v1 does not support installing OS dependencies from locally bundled Ubuntu
packages. Use approved internal Ubuntu/OS package repositories for OS packages
on target hosts.

The Jenkins agent runtime account and group must already exist, and its passwd
HOME must be `/var/lib/jenkins-agent`. Create the account and group through
administrator-controlled OS procedures before continuing.

### 2.2 Create the Agent Artifact Bundle

Run on the bundle-factory VM:

```bash
mkdir -p ~/jenkins-agent-artifacts-bundle/jenkins-agent
cd ~/jenkins-agent-artifacts-bundle
cat > jenkins-agent/manifest.txt <<'EOF'
harness_manifest_version=1
role=jenkins-agent
bundle_name=jenkins-agent-artifacts-bundle
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=not-applicable
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
bootstrap=jenkins-agent-bootstrap.txt
template_count=2
EOF
printf 'Jenkins SSH agent bootstrap marker for Ubuntu 24.04 noble with OpenJDK 21.\n' \
  > jenkins-agent/jenkins-agent-bootstrap.txt
(cd jenkins-agent && find . -type f ! -name checksums.sha256 -print0 \
  | sort -z | xargs -0 sha256sum > checksums.sha256)
tar -czf ~/jenkins-agent-artifacts-bundle.tar.gz -C ~/jenkins-agent-artifacts-bundle jenkins-agent
sha256sum ~/jenkins-agent-artifacts-bundle.tar.gz > ~/jenkins-agent-artifacts-bundle.tar.gz.sha256
```

### 2.3 Install the Agent Artifact Bundle Manually

Transfer the agent artifact archive and `.sha256` file to the build-agent
host. The staged archive must not carry Gerrit, Jenkins, or agent SSH key
material. Jenkins controller keypair generation and public-key installation are
later integration-step work.

Verify the artifact archive and internal checksums on the build server, stage
the payload under `/var/lib/loopforge/staging`, then configure the runtime
account and SSH service:

```bash
operator_account="${LOOPFORGE_OPERATOR_ACCOUNT:-ci-operator}"
operator_group="${LOOPFORGE_OPERATOR_GROUP:-$operator_account}"
operator_home="$(getent passwd "$operator_account" | cut -d: -f6)"
[ -n "$operator_home" ] || {
  printf 'missing operator account: %s\n' "$operator_account" >&2
  exit 1
}

cd "$operator_home"
sha256sum -c jenkins-agent-artifacts-bundle.tar.gz.sha256

sudo bash -s "$operator_account" "$operator_group" "$operator_home" <<'EOF'
set -euo pipefail
operator_account="${1:?operator account required}"
operator_group="${2:?operator group required}"
operator_home="${3:?operator home required}"
agent_user=jenkins-agent
agent_uid=61030
agent_gid=61030
remote_fs=/var/lib/jenkins-agent
staging=/var/lib/loopforge/staging
install -d -m 0750 -o "$operator_account" -g "$operator_group" "$staging"
rm -rf "$staging/jenkins-agent"
tar -xzf "$operator_home/jenkins-agent-artifacts-bundle.tar.gz" -C "$staging"
chown -R "$operator_account:$operator_group" "$staging/jenkins-agent"
cd "$staging/jenkins-agent"
sha256sum -c checksums.sha256
if ! getent group "${agent_user}" >/dev/null; then
  groupadd --gid "${agent_gid}" "${agent_user}"
fi
if ! getent passwd "${agent_user}" >/dev/null; then
  useradd --uid "${agent_uid}" --gid "${agent_gid}" --home-dir "${remote_fs}" --shell /bin/bash "${agent_user}"
fi
install -d -o "${agent_user}" -g "${agent_user}" -m 0750 "${remote_fs}"
rm -f "${remote_fs}/remoting.jar"
systemctl enable --now ssh || systemctl enable --now sshd || true
EOF
```

For artifact recovery, rerun only the artifact archive checksum, transfer,
internal checksum, account, remote filesystem, and SSH service commands. OS
package recovery uses the approved internal Ubuntu/OS package repository path.

## 3. Jenkins Agent Installation

### 3.1 Shared Integration Handoff

Agent host-only bringup does not consume controller key material, validate
controller SSH access, update `authorized_keys`, register a Jenkins node, or
prove controller scheduling. The agent role proves OS/tooling readiness, the
dedicated runtime account, remote filesystem ownership, the SSH daemon, staged
artifacts, bounded logs, and role-local evidence.

Later Jenkins-to-agent public-key authorization, Jenkins node registration,
scheduling validation, and key rotation belong to
`docs/operations/native/integration.md`, not this agent role-local native
reference. Until that workflow is implemented, this native reference remains
limited to agent host readiness.

When the shared integration workflow begins, perform Jenkins-side node
registration through the Jenkins Web UI steps in
`docs/operations/native/integration.md`. This agent reference only prepares
the build server OS, OpenSSH service, runtime account, remote filesystem, and
artifact staging needed by that later UI operation.

Credential custody remains fixed: the Jenkins controller owns the
Jenkins-to-agent private key, and the agent host consumes only the matching
public key. Agent evidence may record public-key fingerprints, accounts,
endpoints, bounded log paths, and redaction status, but never private keys,
passwords, tokens, or LDAP bind secrets.

### 3.2 Configure Build Server Runtime Account

The build server needs a dedicated local runtime account, a remote filesystem,
a running SSH service, and host-side tooling. The artifact install in section
2.3 performs those host-only steps. Controller key installation and
`authorized_keys` mutation are deferred.

Install OS packages only from configured apt repositories. Stage Jenkins agent
application artifacts with section 2.3.

## 4. Validation

Run on the agent host:

```bash
java -version
getent passwd jenkins-agent
systemctl is-enabled ssh || systemctl is-enabled sshd
systemctl is-active ssh || systemctl is-active sshd
```

Acceptance checks:

- OpenJDK 21 is active on the build server.
- The `jenkins-agent` runtime account exists.
- The agent remote FS exists and is owned by `jenkins-agent`.
- SSH service is enabled and active on the build server.
- The SSH daemon returns a real OpenSSH banner on the agent port.
- Jenkins controller node registration, controller-side SSH launch,
  scheduling-label proof, later integration validation jobs, Gerrit Trigger
  execution, and `Verified` vote proof are deferred to the later shared
  integration workflow.

This guest OpenSSH service is the lifecycle owner for the outbound SSH agent.
There is no separate `jenkins-agent.service`.

## 5. Backup and Operations

Record the agent host, SSH endpoint, runtime user, remote FS path, Jenkins
node name, and scheduling labels with the later integration handoff.

Jenkins-to-agent key rotation belongs to
`docs/operations/native/integration.md`. It must preserve
Jenkins-controller private-key custody and provide only the matching public key
to the agent host.

For package baseline changes, update the approved internal Ubuntu/OS package
repository state and reinstall agent dependencies before repeating host-only
validation. Smoke-job validation remains later integration work. For account,
key, or SSH service recovery, reinstall only the agent artifact bundle.

## 6. References

- Jenkins controller native operations:
  `docs/operations/native/jenkins-controller.md`
- Integration native operations:
  `docs/operations/native/integration.md`
- Jenkins SSH Build Agents plugin: https://plugins.jenkins.io/ssh-slaves/
- Jenkins distributed builds documentation: https://www.jenkins.io/doc/book/using/using-agents/
