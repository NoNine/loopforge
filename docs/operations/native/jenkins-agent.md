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
- The agent target is freshly provisioned with no prior Jenkins agent or
  Loopforge runtime state, including no agent runtime account, group, or
  `/var/lib/jenkins-agent` path.
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

Role installation creates the dedicated `jenkins-agent` account and product
home; OS dependency setup enables SSH. Neither step installs Jenkins controller
keys. Controller credential selection, node registration, and scheduling proof
are later integration work.

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

Review the Jenkins agent runtime account/group names and numeric IDs before
installation. This clean-install procedure creates them on the freshly
provisioned target. If a reviewed name, numeric ID, or product-home path is
already in use, stop and reprovision the target.

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

Transfer the agent artifact archive and `.sha256` file to the operator home on
the build-agent host. The staged archive must not carry Gerrit, Jenkins, or
agent SSH key material. Jenkins controller keypair generation and public-key
installation are later integration-step work.

Set the reviewed operator account values and verify the transferred archive.
Run the remaining commands in this section from the same operator shell so
these values remain available:

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
```

This is a clean-install procedure. Run these read-only checks before staging
artifacts or creating the runtime identity and product home. The four `getent`
commands must return no entry, and the final `test` must succeed. If a command
finds an existing name, numeric ID, or path, stop and reprovision the target
instead of adapting or repairing it in place:

```bash
getent passwd jenkins-agent
getent group jenkins-agent
getent passwd 61030
getent group 61030
test ! -e /var/lib/jenkins-agent
```

After preflight succeeds, replace the disposable extracted staging tree and
verify every staged file. The `rm` command below removes only the Jenkins agent
staging payload; it does not remove the transferred archive or the agent
product home:

```bash
sudo install -d -m 0750 -o "$operator_account" -g "$operator_group" \
  /var/lib/loopforge/staging
sudo rm -rf -- /var/lib/loopforge/staging/jenkins-agent
sudo tar -xzf "$operator_home/jenkins-agent-artifacts-bundle.tar.gz" \
  -C /var/lib/loopforge/staging
sudo chown -R "$operator_account:$operator_group" \
  /var/lib/loopforge/staging/jenkins-agent
cd /var/lib/loopforge/staging/jenkins-agent
sha256sum -c checksums.sha256
```

Create the reviewed runtime group, account, and product home:

```bash
sudo groupadd --gid 61030 jenkins-agent
sudo useradd --uid 61030 --gid 61030 \
  --home-dir /var/lib/jenkins-agent --no-create-home \
  --shell /bin/bash jenkins-agent
sudo install -d -m 0755 -o jenkins-agent -g jenkins-agent \
  /var/lib/jenkins-agent
```

Ubuntu 24.04 provides the OpenSSH server as the `ssh` systemd unit. Enable and
start that unit; do not continue if this command fails:

```bash
sudo systemctl enable --now ssh
```

For artifact recovery after installation, rerun only the artifact archive
checksum, transfer, extraction, and internal checksum commands. Do not rerun
the clean-install preflight, account creation, or product-home creation
commands. OS package recovery uses the approved internal Ubuntu/OS package
repository path.

## 3. Jenkins Agent Installation

### 3.1 Shared Integration Handoff

Agent host-only bringup does not consume controller key material, validate
controller SSH access, update `authorized_keys`, register a Jenkins node, or
prove controller scheduling. The agent role proves OS/tooling readiness, the
dedicated runtime account, remote filesystem ownership, the SSH daemon, staged
artifacts, and bounded log inspection.

Later Jenkins-to-agent public-key authorization, Jenkins node registration,
scheduling validation, and key rotation belong to
`docs/operations/native/integration.md`, not this agent role-local native
reference. The manual integration workflow is available; this native reference
remains limited to agent host readiness.

When the shared integration workflow begins, perform Jenkins-side node
registration through the Jenkins Web UI steps in
`docs/operations/native/integration.md`. This agent reference only prepares
the build server OS, OpenSSH service, runtime account, remote filesystem, and
artifact staging needed by that later UI operation.

Credential custody remains fixed: the Jenkins controller owns the
Jenkins-to-agent private key, and the agent host consumes only the matching
public key. Do not create a separate agent evidence record. Record the required
role outcomes only in `docs/operations/native/acceptance-checklist.md`. Do not
place private keys, passwords, tokens, LDAP bind secrets, or secret-bearing
configuration in the checklist or its three references.

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

The reboot check is optional. To perform it, use the site's reviewed reboot
procedure, wait for the target to return, and rerun the validation above
without starting, enabling, or repairing the SSH service. Leave the optional
checklist item unchecked when the check is not performed. If the check is
attempted and the agent does not return to the same ready state,
mark the run `BLOCKED`.

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
