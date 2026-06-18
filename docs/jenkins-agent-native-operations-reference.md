# Jenkins Agent Native Operations Reference

This document is a native operations reference. It uses OS and
application-native operations only, not repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Agent bootstrap artifacts, including the agent-side public key artifact, are
prepared in the bundle-factory environment and staged to the target before any
mutation. Public internet fallback on target hosts is simulation-only and must
be labeled as such in docs, logs, and verification summaries.


Audience: production operators preparing a Jenkins outbound SSH build agent on
Ubuntu 24.04 LTS without Docker.

Use this manual with `jenkins-controller-native-operations-reference.md`. The
Jenkins controller manual covers controller installation and controller-only
configuration. Controller-side node registration, Gerrit integration, and
Jenkins scheduling proof are later integration-step work. This manual covers
the build server baseline, agent application artifacts, SSH access, recovery,
and agent host-only validation.

Assumptions:

- Jenkins runs on its own Ubuntu 24.04 LTS host.
- The build agent runs on a separate Ubuntu 24.04 LTS host.
- Jenkins connects out to the build agent over SSH.
- The build agent exposes SSH only on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Jenkins agent application artifacts.
- Production host commands are run with `sudo` or equivalent delegated
  administrator privileges unless noted.

Recommended versions as of 2026-06-09:

- Java: OpenJDK 21.
- Jenkins agent launcher: Jenkins SSH Build Agents plugin from the controller
  plugin bundle.

Production warning: do not run builds on the Jenkins controller. Keep the
built-in node at zero executors and provide build capacity through agents.

Privilege warning: agent setup cannot be completed by an unprivileged user
alone. Package installation, local runtime accounts, SSH service control, and
remote filesystem ownership require root or delegated sudo on the build
server.

Manual authority: this manual is the reference procedure. It intentionally
contains only native OS, OpenSSH, and Jenkins UI/application operations. Do not
add repository automation commands or automation-equivalent command tables to
this document.

## 1. Operator Inputs and Current Status

Record these values before installation:

| Item | Value |
| --- | --- |
| Jenkins controller host | `JENKINS_HOST` |
| Jenkins HTTP port | `8080` or chosen port |
| Agent host | `JENKINS_AGENT_HOST` |
| Agent SSH port | `22` or chosen port |
| Agent runtime user | `JENKINS_AGENT_USER`, normally `jenkins-agent` |
| Agent remote FS | `JENKINS_AGENT_REMOTE_FS`, normally `/var/lib/jenkins-agent` |
| Agent node name | `JENKINS_AGENT_NAME`, for example `build-linux-x86-01` |
| Agent labels | `JENKINS_AGENT_LABELS`, for example `linux x86_64 general-build gerrit-ci` |
| Agent executors | `JENKINS_AGENT_EXECUTORS`, for example `5` |
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

### 2.1 OS Dependency Setup

OS dependency setup installs the minimal build base from the build server's
approved apt repositories, creates the dedicated `jenkins-agent` account, and
enables SSH. The build server package baseline is owned by this agent-host
reference. It does not install Jenkins controller keys; controller credential
selection, node registration, and scheduling proof are later integration work.

Manual package baseline on the build server:

```bash
apt update
apt install -y \
  build-essential \
  ca-certificates \
  curl \
  git \
  openssh-client \
  openssh-server \
  openjdk-21-jre \
  rsync \
  sudo \
  tar \
  unzip \
  wget
java -version
```

Set `JENKINS_BUILD_EXTRA_PACKAGES` for site-wide packages needed on every
general build agent. Keep project-specific toolchains outside the default
baseline unless every general build agent needs them.

v1 does not support installing OS dependencies from locally bundled Ubuntu
packages. Use approved internal Ubuntu/OS package repositories for OS packages
on target hosts.

### 2.2 Create the Agent Artifact Bundle

Run on the bundle-factory VM:

```bash
mkdir -p ~/jenkins-agent-artifacts-bundle/{jenkins-agent,checksums}
cd ~/jenkins-agent-artifacts-bundle
printf 'bundle_kind=jenkins-agent-artifacts\nbootstrap=bundle-factory-owned\n' \
  > jenkins-agent/release-unit.manifest
find . -type f ! -path './checksums/SHA256SUMS' -print0 \
  | sort -z | xargs -0 sha256sum > checksums/SHA256SUMS
tar -czf ~/jenkins-agent-artifacts-bundle.tar.gz -C ~ jenkins-agent-artifacts-bundle
sha256sum ~/jenkins-agent-artifacts-bundle.tar.gz > ~/jenkins-agent-artifacts-bundle.tar.gz.sha256
```

### 2.3 Install the Agent Artifact Bundle Manually

Transfer the agent artifact archive and `.sha256` file to the build-agent
host. The staged archive already carries the agent-side public key artifact;
do not treat that as Jenkins controller key handoff during host-only setup.

Verify the artifact archive and internal checksums on the build server, then
configure the runtime account and SSH service:

```bash
sha256sum -c /home/operator/jenkins-agent-artifacts-bundle.tar.gz.sha256

sudo bash -s <<'EOF'
set -euo pipefail
agent_user=jenkins-agent
remote_fs=/var/lib/jenkins-agent
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
tar -xzf /home/operator/jenkins-agent-artifacts-bundle.tar.gz -C "$workdir"
cd "$workdir/jenkins-agent-artifacts-bundle"
sha256sum -c checksums/SHA256SUMS
if ! getent group "${agent_user}" >/dev/null; then
  groupadd --system "${agent_user}"
fi
if ! getent passwd "${agent_user}" >/dev/null; then
  useradd --system --gid "${agent_user}" --home-dir "${remote_fs}" --shell /bin/bash "${agent_user}"
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

### 3.1 Later Controller SSH Public Key Integration

The Jenkins controller will use its private key to launch the SSH agent during
the later integration step. Agent host-only bringup does not consume
controller key material, validate controller SSH access, or prove controller
scheduling. Generate or confirm the keypair on the Jenkins controller during
that later integration workflow:

```bash
sudo install -d -o jenkins -g jenkins -m 0700 /var/lib/jenkins/.ssh
if [ ! -f /var/lib/jenkins/.ssh/agent_ed25519 ]; then
  sudo -u jenkins ssh-keygen -t ed25519 \
    -f /var/lib/jenkins/.ssh/agent_ed25519 \
    -C jenkins-agent-agent \
    -N ''
fi
sudo chmod 0600 /var/lib/jenkins/.ssh/agent_ed25519
sudo chmod 0644 /var/lib/jenkins/.ssh/agent_ed25519.pub
```

During the later integration step, copy only
`/var/lib/jenkins/.ssh/agent_ed25519.pub` to the agent host and append it to
the runtime account's `authorized_keys`.

### 3.2 Configure Build Server Runtime Account

The build server needs a dedicated local runtime account, a remote filesystem,
a running SSH service, and host-side tooling. The artifact install in section
2.3 performs those host-only steps. Controller key installation is deferred.

Install OS packages only from configured apt repositories. Stage Jenkins agent
application artifacts with section 2.3.

### 3.3 Configure Jenkins Node

After the build server is prepared, configure the permanent SSH node in
Jenkins. The build-server package and SSH setup do not create the Jenkins
credential or node; perform controller-side registration in Jenkins.

Use stable inventory-style node names and composable labels:

```bash
JENKINS_AGENT_NAME=build-linux-x86-01
JENKINS_AGENT_LABELS="linux x86_64 general-build gerrit-ci"
JENKINS_AGENT_EXECUTORS=5
JENKINS_AGENT_HOST=192.168.122.209
JENKINS_AGENT_PORT=22
JENKINS_AGENT_USER=jenkins-agent
JENKINS_AGENT_REMOTE_FS=/var/lib/jenkins-agent
```

During the later integration step, create an SSH credential for
`JENKINS_AGENT_USER` using `JENKINS_AGENT_SSH_KEY`, then create a permanent SSH
agent with the configured host, port, remote FS, executor count, and labels.
Do not treat that controller-side node registration as agent host-only
bringup.

## 4. Validation

Run on the agent host:

```bash
java -version
git --version
getent passwd jenkins-agent
systemctl is-active ssh || systemctl is-active sshd
```

Acceptance checks:

- OpenJDK 21 is active on the build server.
- The `jenkins-agent` runtime account exists.
- The agent remote FS exists and is owned by `jenkins-agent`.
- SSH service is active on the build server.
- The SSH daemon returns a real OpenSSH banner on the agent port.
- Jenkins controller node registration, controller-side SSH launch,
  scheduling, later integration validation jobs, Gerrit Trigger execution, and
  `Verified` vote proof are deferred to the later integration step.

## 5. Backup and Operations

Record the agent inventory values, labels, executor count, SSH endpoint, and
remote FS path with the Jenkins controller handoff.

Protect the Jenkins controller private key:

```bash
sudo ls -l /var/lib/jenkins/.ssh/agent_ed25519
sudo chmod 0600 /var/lib/jenkins/.ssh/agent_ed25519
```

When rotating the controller key during later integration, copy the new `.pub`
file to the agent host and update `authorized_keys` there so the authorized key
is refreshed. Coordinate this with a quiet build window because running builds
can lose their agent connection.

For package baseline changes, update the approved internal Ubuntu/OS package
repository state and reinstall agent dependencies before repeating host-only
validation. Smoke-job validation remains later integration work. For account,
key, or SSH service recovery, reinstall only the agent artifact bundle.

## 6. References

- Jenkins controller native operations:
  `jenkins-controller-native-operations-reference.md`
- Jenkins SSH Build Agents plugin: https://plugins.jenkins.io/ssh-slaves/
- Jenkins distributed builds documentation: https://www.jenkins.io/doc/book/using/using-agents/
