# Jenkins Agent Native Operations Reference

This document is the manual `target-deployment` native operations reference
for the Jenkins SSH build agent. It uses direct OS and OpenSSH operations only,
not repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages.
Target hosts use approved internal Ubuntu/OS package repositories for OS
dependencies. Agent bootstrap artifacts are prepared in the bundle-factory
environment and staged to the target before account, filesystem, or service
mutation. Artifact bundles must not include Gerrit, Jenkins, or agent SSH key
material. Public internet fallback for target-host Ubuntu/OS dependency
installation is simulation-only and must be labeled as such.

Audience: production operators preparing a Jenkins outbound SSH build agent on
Ubuntu 24.04 LTS without Docker.

Use this manual with `docs/operations/native/jenkins-controller.md`. Complete
this role-local procedure before using `docs/operations/native/integration.md`.
Controller key creation, agent public-key authorization, node registration,
shared storage, scheduling, Gerrit Trigger, and `Verified` proof are later
integration work.

Assumptions:

- Jenkins and the build agent run on separate Ubuntu 24.04 LTS hosts.
- The agent target is freshly provisioned with no prior Jenkins agent or
  Loopforge runtime state.
- Jenkins connects out to the build agent over SSH on a trusted/internal
  network.
- The site owns the SSH listener addresses, ports, firewall rules, and global
  access policy. This role owns only the agent account policy and service
  readiness checks.
- Production commands run as the operator account with delegated privilege.
  Root is not a Loopforge account or supported direct login identity.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, OpenSSH
server/client tooling, and the Jenkins SSH Build Agents plugin from the
controller plugin bundle. `docs/baselines/version-baseline.md` owns the
package-wide baseline and reviewed update rules.

Production warning: keep the Jenkins controller built-in node at zero
executors. Build capacity comes from agents.

## 1. Operator Inputs and Current Status

Record these values before installation:

| Item | Value |
| --- | --- |
| Agent host | `JENKINS_AGENT_HOST`, a site-approved stable hostname |
| Agent SSH port | `JENKINS_AGENT_SSH_PORT`, site-managed and normally `22` |
| Agent runtime user | `jenkins-agent`, local OS account |
| Agent runtime group | `jenkins-agent`, local OS group |
| Agent runtime UID | `JENKINS_AGENT_UID`, default `61030` |
| Agent runtime GID | `JENKINS_AGENT_GID`, default `61030` |
| Agent remote FS | `/var/lib/jenkins-agent` |
| Jenkins node name | `JENKINS_AGENT_NODE_NAME`, normally `build-linux-x86-01` |
| Jenkins scheduling labels | `JENKINS_AGENT_LABELS`, normally `linux x86_64 general-build gerrit-ci` |
| Operator account | `LOOPFORGE_OPERATOR_ACCOUNT`, default `ci-operator` |
| Operator group | `LOOPFORGE_OPERATOR_GROUP`, default `ci-operator` |
| Network mode | Approved internal OS repositories for target-host dependencies |

The native baseline runtime account and group are
`jenkins-agent:jenkins-agent`. This clean-install procedure creates them during
installation. If your site uses different values, substitute the reviewed name
and numeric identity consistently everywhere this manual shows the baseline.
The product home remains `/var/lib/jenkins-agent`. The commands intentionally
use the baseline names directly rather than account/group variables.

Run these read-only checks on the agent host:

```bash
cat /etc/os-release
hostnamectl
timedatectl
df -h /var/lib
free -h
systemctl --failed
getent hosts JENKINS_AGENT_HOST
```

Confirm the OS reports Ubuntu `24.04` and `noble`, the host and time match the
reviewed inventory, storage and memory are sufficient, and failed units have an
approved disposition. The final command must resolve `JENKINS_AGENT_HOST`;
stop and correct endpoint identity if it does not.

Confirm the selected clean-install identities and role-owned paths are absent.
Run each command separately. The four `getent` commands must return no entry,
and both `test` commands must succeed:

```bash
getent passwd jenkins-agent
getent group jenkins-agent
getent passwd JENKINS_AGENT_UID
getent group JENKINS_AGENT_GID
test ! -e /var/lib/jenkins-agent
sudo test ! -e /etc/ssh/sshd_config.d/40-jenkins-agent.conf
```

If a reviewed name, numeric ID, product home, or role-owned SSH policy path is
already present, stop and reprovision the target. Do not adapt, overwrite, or
repair it within this clean-install procedure.

### 1.1 If You Do Not Have Root Privileges

Without delegated administrator privilege, use this manual as an administrator
handoff. An administrator must perform or delegate package installation,
runtime identity creation, protected path ownership, SSH policy installation,
and SSH service operations. Do not switch the workflow to direct root login.

## 2. Dependencies And Jenkins Agent Artifact Bundle

### 2.1 Install Ubuntu Dependencies

The package rationale and layered classification are maintained in
`docs/baselines/package-requirements.md`. Run on the agent target:

```bash
sudo apt update
sudo apt install -y \
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

The Java command must report OpenJDK 21. Add site-wide build packages to the
reviewed package operation only when every general agent requires them. Keep
project-specific toolchains outside this host baseline.

### 2.2 Create The Agent Artifact Bundle

Run on the bundle-factory VM. The three freshness checks must succeed. Stop and
select a fresh bundle path if any selected path already exists:

```bash
test ! -e "$HOME/jenkins-agent-artifacts-bundle"
test ! -e "$HOME/jenkins-agent-artifacts-bundle.tar.gz"
test ! -e "$HOME/jenkins-agent-artifacts-bundle.tar.gz.sha256"
mkdir -p "$HOME/jenkins-agent-artifacts-bundle/jenkins-agent"
printf 'Jenkins SSH agent bootstrap marker for Ubuntu 24.04 noble with OpenJDK 21.\n' \
  > "$HOME/jenkins-agent-artifacts-bundle/jenkins-agent/jenkins-agent-bootstrap.txt"
(cd "$HOME/jenkins-agent-artifacts-bundle/jenkins-agent" && \
  find . -type f ! -name checksums.sha256 -print0 \
  | sort -z | xargs -0 sha256sum > checksums.sha256)
cd "$HOME"
tar -czf jenkins-agent-artifacts-bundle.tar.gz \
  -C jenkins-agent-artifacts-bundle jenkins-agent
sha256sum jenkins-agent-artifacts-bundle.tar.gz \
  > jenkins-agent-artifacts-bundle.tar.gz.sha256
```

The native release unit is the archive, its sibling checksum file, the
bootstrap marker, and the payload checksum inventory. It contains no native
manifest or template set. Review the payload inventory and archive checksum in
the deployment change or ticket. Do not add private keys, public keys,
`authorized_keys`, passwords, tokens, or secret-bearing configuration.

### 2.3 Stage And Verify The Agent Artifact Bundle

Transfer the archive and sibling `.sha256` file to the operator's home on the
agent host. Replace the uppercase operator placeholders below with reviewed
values, then run each command separately:

```bash
getent passwd LOOPFORGE_OPERATOR_ACCOUNT
getent group LOOPFORGE_OPERATOR_GROUP
cd "$HOME"
sha256sum -c jenkins-agent-artifacts-bundle.tar.gz.sha256
sudo test ! -e /var/lib/loopforge/staging/jenkins-agent
sudo install -d -m 0750 \
  -o LOOPFORGE_OPERATOR_ACCOUNT \
  -g LOOPFORGE_OPERATOR_GROUP \
  /var/lib/loopforge/staging
sudo tar -xzf jenkins-agent-artifacts-bundle.tar.gz \
  -C /var/lib/loopforge/staging
sudo chown -R \
  LOOPFORGE_OPERATOR_ACCOUNT:LOOPFORGE_OPERATOR_GROUP \
  /var/lib/loopforge/staging/jenkins-agent
cd /var/lib/loopforge/staging/jenkins-agent
sha256sum -c checksums.sha256
```

The identity lookups must return the reviewed operator identities, both
checksum commands must pass, and the staging freshness test must succeed.
Stop and reprovision the clean target if staging already exists. Do not create
runtime identity, product-home state, or SSH service state until payload
verification passes.

## 3. Jenkins Agent Installation

### 3.1 Create The Runtime Identity And Product Home

Create the reviewed runtime group, account, and fixed product home:

```bash
sudo groupadd --gid JENKINS_AGENT_GID jenkins-agent
sudo useradd --uid JENKINS_AGENT_UID --gid JENKINS_AGENT_GID \
  --home-dir /var/lib/jenkins-agent --no-create-home \
  --shell /bin/bash jenkins-agent
sudo usermod -p '*' jenkins-agent
sudo install -d -m 0755 \
  -o jenkins-agent \
  -g jenkins-agent \
  /var/lib/jenkins-agent
```

`useradd` initially creates a locked account on Ubuntu. The immediate
`usermod` operation replaces the locking marker with the impossible password
hash `*`: password authentication cannot succeed, while OpenSSH may use the
account for the later public-key-only Jenkins connection.

### 3.2 Install The Agent Account SSH Policy

The site owns global SSH listener addresses and ports. Before changing service
state, confirm the reviewed agent port is already present in effective sshd
configuration:

```bash
sudo sshd -T | awk -v port="JENKINS_AGENT_SSH_PORT" \
  '$1 == "port" && $2 == port { found=1 } END { exit !found }'
```

The command must succeed. If it fails, stop and use the site's approved SSH,
network, and firewall procedure to provision the reviewed listener. Do not add
or change a global `Port`, `ListenAddress`, or `AllowUsers` directive here.
This is the site SSH/network provisioning stop condition for the role.

Create the role-owned account policy with `sudoedit`:

```bash
sudoedit /etc/ssh/sshd_config.d/40-jenkins-agent.conf
```

```text
# Port and ListenAddress are site-owned.
Match User jenkins-agent
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitEmptyPasswords no
Match all
```

Protect and validate the policy before service mutation:

```bash
sudo chown root:root /etc/ssh/sshd_config.d/40-jenkins-agent.conf
sudo chmod 0644 /etc/ssh/sshd_config.d/40-jenkins-agent.conf
sudo sshd -t
sudo sshd -T -C \
  user=jenkins-agent,host=JENKINS_AGENT_HOST,addr=127.0.0.1 \
  | awk '
      $1 == "authenticationmethods" && $2 == "publickey" { methods=1 }
      $1 == "pubkeyauthentication" && $2 == "yes" { publickey=1 }
      $1 == "passwordauthentication" && $2 == "no" { password=1 }
      $1 == "kbdinteractiveauthentication" && $2 == "no" { interactive=1 }
      $1 == "permitemptypasswords" && $2 == "no" { empty=1 }
      END { exit !(methods && publickey && password && interactive && empty) }
    '
```

Both commands must succeed. Enable the Ubuntu `ssh` unit and reload the
validated configuration:

```bash
sudo systemctl enable --now ssh
sudo systemctl reload ssh
```

Keep the current operator session open. From the normal control point, prove a
second operator login through the site's existing operator SSH endpoint before
closing the original session. The role-owned `Match User` policy must not
replace site control-plane access policy.

## 4. Shared Integration Handoff

Agent-native role readiness stops before controller-to-agent integration. This
role proves the reviewed runtime account and group, numeric identity,
product-home ownership, staged artifacts, account-scoped SSH policy, site-owned
SSH endpoint, service state, and bounded status inspection. It does not consume
controller key material, update `authorized_keys`, register a Jenkins node,
configure shared storage, or prove scheduling.

Record the agent host, SSH endpoint, runtime account and group, remote FS, node
name, and labels for integration. The Jenkins controller owns the private key;
the agent host later consumes only the matching public key. Perform those
cross-role operations with `docs/operations/native/integration.md` only after
the controller and agent host are both ready.

Record required outcomes only in
`docs/operations/native/acceptance-checklist.md`. Do not place private keys,
passwords, tokens, LDAP bind secrets, or secret-bearing configuration in the
checklist or its three references.

## 5. Agent-Only Validation

Run on the agent host without starting, enabling, reloading, or repairing SSH:

```bash
java -version
systemctl is-enabled ssh
systemctl is-active ssh
systemctl show ssh \
  --property=LoadState --property=UnitFileState \
  --property=ActiveState --property=MainPID --no-pager
ssh-keyscan -T 5 -p JENKINS_AGENT_SSH_PORT JENKINS_AGENT_HOST
sudo systemctl status ssh --no-pager --lines=20
```

Acceptance results:

- Java reports OpenJDK 21.
- `ssh.service` is loaded, enabled, and active with a nonzero `MainPID`.
- `ssh-keyscan` returns OpenSSH host-key output from the reviewed agent endpoint.
- The bounded service status contains no startup or configuration failure.

Section 2 owns archive and payload checksum verification. Section 3 owns the
runtime identity, product-home ownership, account shadow state, and effective
sshd policy checks. Do not replay those earlier checkpoint operations during
role validation.

The reboot check is optional. To perform it, use the site's reviewed reboot
procedure, wait for the target to return, and rerun this validation without
starting, enabling, reloading, or repairing SSH. Leave the optional checklist
item unchecked when the check is not performed. If the check is attempted and
the agent does not return to the same ready state, mark the run `BLOCKED`.

The guest OpenSSH service is the lifecycle owner for the outbound SSH agent.
There is no separate `jenkins-agent.service`.

## 6. Backup and Operations

Retain the approved native agent archive, sibling checksum, package inventory,
reviewed account values, SSH endpoint, node name, and labels with the deployment
change. Agent workspaces are execution state, not the authoritative recovery
unit for source or build outputs. Protect authoritative outputs through their
project or shared-storage retention policy.

Do not reinstall the artifact bundle to repair an account, key, product home,
or SSH service. Preserve bounded diagnostics, reprovision a fresh agent target,
and rerun this procedure. Package-source or site SSH listener failures belong
to their owning site procedures. Jenkins-to-agent key replacement and rotation
belong to `docs/operations/native/integration.md`.

## 7. References

- Jenkins controller native operations:
  `docs/operations/native/jenkins-controller.md`
- Integration native operations:
  `docs/operations/native/integration.md`
- Jenkins SSH Build Agents plugin: https://plugins.jenkins.io/ssh-slaves/
- Jenkins distributed builds: https://www.jenkins.io/doc/book/using/using-agents/
- OpenSSH server configuration: https://man.openbsd.org/sshd_config
