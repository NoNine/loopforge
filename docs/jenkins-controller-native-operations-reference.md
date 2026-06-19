# Jenkins Controller Native Operations Reference

This document is a native operations reference. It uses OS and
application-native operations only, not repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Public internet fallback on target hosts is simulation-only and must be labeled
as such in docs, logs, and verification summaries.

Jenkins controller application artifact bundles are key-free. They may contain
reviewed Jenkins application files, plugin artifacts, JCasC/config templates,
job definitions, manifests, and checksums, but not SSH private keys, public
keys, `authorized_keys`, or generated public-key handoff files.
Jenkins-to-Gerrit and Jenkins-to-agent keypair generation and public-key
handoff are integration operations after controller role-local readiness is
proven.


Audience: production operators installing Jenkins on Ubuntu 24.04 LTS without Docker.

Use this controller manual with `jenkins-agent-native-operations-reference.md`
when the deployment includes outbound SSH build agents. This document covers
controller-only bringup through Jenkins runtime, LDAP/JCasC, plugin, service,
and endpoint readiness. Gerrit Trigger setup, Jenkins-to-Gerrit keys,
controller node registration, scheduling proof, and `Verified` vote proof are
later integration-step work.

Assumptions:

- Jenkins runs on its own Ubuntu 24.04 LTS host.
- Gerrit runs on a separate host and is reachable from Jenkins.
- Identity is integrated with LDAP/Active Directory.
- Jenkins exposes a direct service port on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Jenkins controller application artifacts.
- Production host commands are run with `sudo` or equivalent delegated administrator privileges unless noted.

Recommended versions as of 2026-06-09:

- Jenkins: `2.555.3 LTS` from the official `debian-stable` package repository.
- Java: OpenJDK 21.

Production warning: direct HTTP service ports are documented because that is the selected deployment model. For production environments outside a trusted network, terminate TLS with a reverse proxy or enterprise load balancer before exposing Jenkins to users.

Privilege warning: a production Jenkins install cannot be completed by an unprivileged user alone. Package installation, `/etc`, `/opt`, `/var/lib/jenkins`, file ownership, systemd overrides, service restarts, and root-owned secret files require root or delegated sudo.

Manual authority: this manual is the reference procedure. It intentionally
contains only native OS and Jenkins operations. Do not add repository
automation commands or automation-equivalent command tables to this document.


## 1. Operator Inputs and Current Status

Record these values before installation:

| Item | Value |
| --- | --- |
| Hostname | `JENKINS_HOST` |
| IP address | `JENKINS_IP` |
| DNS name | `jenkins.example.internal` |
| HTTP port | `8080` or chosen port |
| Gerrit host | `GERRIT_HOST` |
| Gerrit HTTP port | `8080` or chosen port |
| Gerrit SSH port | `29418` |
| LDAP URL | `ldap://LDAP_HOST:389` or `ldaps://LDAP_HOST:636` |
| LDAP bind DN | `uid=jenkins-ldap-bind,LDAP_USER_BASE` or provided bind DN |
| LDAP user base | `LDAP_USER_BASE` |
| LDAP group base | `LDAP_GROUP_BASE` |
| Network mode | Approved internal OS repositories for target-host OS dependencies |
| Jenkins runtime user | `jenkins`, local OS account |
| Jenkins runtime group | `jenkins`, local OS group |
| Jenkins Gerrit integration account | `jenkins-gerrit`, Gerrit-internal account |
| Jenkins home | `/var/lib/jenkins`, owned by `jenkins:jenkins` |

Run on the Jenkins host:

```bash
lsb_release -a
hostnamectl
timedatectl
ip addr
ip route
df -h
free -h
java -version || true
apt policy
dpkg -l | egrep 'openjdk|jenkins|git|curl|wget|openssh|fontconfig|netcat' || true
systemctl --failed
ss -lntup
getent hosts JENKINS_HOST GERRIT_HOST
getent passwd jenkins
getent group jenkins
nc -vz GERRIT_HOST 8080 || true
nc -vz GERRIT_HOST 29418 || true
nc -vz LDAP_HOST 389 || true
nc -vz LDAP_HOST 636 || true
```

Use port `389` for LDAP with StartTLS if required. Use port `636` for LDAPS.

The Jenkins runtime user and group are local OS identities. If the Jenkins
package creates `jenkins:jenkins`, use that account. If your site requires a
different local account, create it before configuring the service and use that
same value everywhere this manual shows `jenkins`.

The LDAP bind DN used by Jenkins should be a dedicated read-only Jenkins bind
account. It must have permission to search the configured user and group bases.
A bind account that can authenticate but cannot search those subtrees will
still cause Jenkins login and group resolution failures.

### 1.1 If You Do Not Have Root Privileges

Use this manual as an administrator handoff. Without root, you can prepare
Jenkins controller application artifacts on a permitted staging machine, draft
JCasC settings, collect required host/DNS/LDAP values, and run network checks
that your account is allowed to run.

Ask an administrator to perform or delegate these production-host tasks:

- Install OS packages, configure the Jenkins package repository, install `jenkins=2.555.3`, and apply package holds.
- Confirm the local Jenkins runtime account and group exist on the Jenkins host.
- Create and own `/var/lib/jenkins`, `/var/lib/jenkins/plugins`,
  `/var/lib/jenkins/casc`, and any staged `/opt/jenkins-artifacts-bundle`
  content as documented.
- Create `/etc/jenkins-casc.env`, set `0600`, and keep it owned by `root:root`.
- Create or edit the Jenkins systemd override, reload systemd, and start, stop, restart, or enable Jenkins.
- Run any `chown`, `chmod`, `apt`, `dpkg`, `systemctl`, or writes under `/etc`, `/opt`, or `/var/lib`.

A home-directory Jenkins process can be useful for lab validation, but it is not this production deployment. It will not match the documented package lifecycle, systemd service management, ownership model, backup paths, or secret handling.

## 2. Dependencies And Jenkins Controller Artifact Bundle

### 2.1 OS Dependency And Repository Setup

Run on the Jenkins host:

```bash
apt update
apt install -y \
  ca-certificates \
  curl \
  fontconfig \
  git \
  net-tools \
  netcat-openbsd \
  openjdk-21-jre \
  openssh-client \
  rsync \
  tar \
  unzip \
  wget
java -version
```

Configure the official Jenkins stable package repository:

```bash
install -d -m 0755 /etc/apt/keyrings
wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
apt update
```

### 2.2 Jenkins Controller Artifact Bundle

v1 does not support installing OS dependencies from locally bundled Ubuntu
packages. Use approved internal Ubuntu/OS package repositories for OS packages
on target hosts.

Prepare Jenkins controller application artifacts in staging or a bundle-factory
environment, then stage only the reviewed application artifact archive to the
Jenkins controller host.

Official source references:

```text
https://pkg.jenkins.io/debian-stable/binary/jenkins_2.555.3_all.deb
https://get.jenkins.io/war-stable/2.555.3/jenkins.war
https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar
https://updates.jenkins.io/download/plugins
```

#### 2.2.1 Create the Controller Artifact Bundle

Run on the bundle-factory VM:

```bash
mkdir -p ~/jenkins-artifacts-bundle/{jenkins/plugins,checksums,tools}
cd ~/jenkins-artifacts-bundle/jenkins
wget https://pkg.jenkins.io/debian-stable/binary/jenkins_2.555.3_all.deb
wget -O jenkins-2.555.3.war \
  https://get.jenkins.io/war-stable/2.555.3/jenkins.war
cat > plugins.intent.txt <<'EOF'
configuration-as-code
credentials
git
gerrit-trigger
ldap
matrix-auth
ssh-credentials
ssh-slaves
workflow-aggregator
job-dsl
timestamper
ws-cleanup
EOF
```

`plugins.intent.txt` is the operator-owned direct plugin intent, names only.
Do not add transitive dependencies to this file only because they appear in
Plugin Installation Manager resolver output.

Download and verify the Jenkins Plugin Installation Manager Tool:

```bash
cd ~/jenkins-artifacts-bundle/tools
wget https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar
wget https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar.sha256
if grep -q '[[:space:]]' jenkins-plugin-manager-2.15.0.jar.sha256; then
  sha256sum -c jenkins-plugin-manager-2.15.0.jar.sha256
else
  printf '%s  jenkins-plugin-manager-2.15.0.jar\n' \
    "$(cat jenkins-plugin-manager-2.15.0.jar.sha256)" | sha256sum -c -
fi
```

Ask the Jenkins Plugin Installation Manager Tool to propose versions for the
direct plugin intent against Jenkins `2.555.3`:

```bash
rm -f \
  ~/jenkins-artifacts-bundle/jenkins/plugin-version-proposals.txt \
  ~/jenkins-artifacts-bundle/jenkins/plugin-version-resolution-report.txt \
  ~/jenkins-artifacts-bundle/jenkins/plugins.lock.txt \
  ~/jenkins-artifacts-bundle/jenkins/plugin-artifacts.manifest \
  ~/jenkins-artifacts-bundle/jenkins/plugin-resolution-report.txt \
  ~/jenkins-artifacts-bundle/jenkins/plugin-review-report.txt
java -jar ~/jenkins-artifacts-bundle/tools/jenkins-plugin-manager-2.15.0.jar \
  --war ~/jenkins-artifacts-bundle/jenkins/jenkins-2.555.3.war \
  --plugin-file ~/jenkins-artifacts-bundle/jenkins/plugins.intent.txt \
  --latest false \
  --no-download \
  --list \
  > ~/jenkins-artifacts-bundle/jenkins/plugin-version-resolution-report.txt
```

Extract direct `plugin-name:version` proposals from the resolver output. Keep
the full resolver output as evidence and verify that every direct plugin was
resolved before accepting:

```bash
cd ~/jenkins-artifacts-bundle/jenkins
awk '
  NR == FNR {
    wanted[$1] = 1
    order[++count] = $1
    next
  }
  {
    line = $0
    gsub(/\r/, "", line)
    sub(/^[[:space:]*-]+/, "", line)
    name = ""
    version = ""
    split(line, fields, /[[:space:]]+/)
    if (fields[1] ~ /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.+-]+$/) {
      split(fields[1], pair, ":")
      name = pair[1]
      version = pair[2]
    } else if (wanted[fields[1]]) {
      name = fields[1]
      version = fields[2]
      gsub(/^[({[]/, "", version)
      gsub(/[)}\],;]$/, "", version)
    }
    if (wanted[name] && version ~ /^[A-Za-z0-9_.+-]+$/) {
      resolved[name] = version
    }
  }
  END {
    missing = 0
    for (i = 1; i <= count; i++) {
      name = order[i]
      if (!(name in resolved)) {
        printf "missing proposal for %s\n", name > "/dev/stderr"
        missing = 1
      } else {
        printf "%s:%s\n", name, resolved[name]
      }
    }
    exit missing
  }
' plugins.intent.txt plugin-version-resolution-report.txt \
  > plugin-version-proposals.txt
```

Review `plugin-version-proposals.txt` and
`plugin-version-resolution-report.txt`. Accept direct pins by recording the
reviewed proposal as the controller's direct plugin list:

```bash
cp plugin-version-proposals.txt accepted-direct-plugins.txt
cp accepted-direct-plugins.txt plugins.seed.txt
```

`plugins.seed.txt` is generated Plugin Installation Manager input from the
accepted direct pins. It is not an operator-owned review artifact. Do not add
transitive dependencies to `accepted-direct-plugins.txt` or `plugins.seed.txt`.

Resolve and download the accepted direct pins and their dependencies:

```bash
rm -rf ~/jenkins-artifacts-bundle/jenkins/plugins
mkdir -p ~/jenkins-artifacts-bundle/jenkins/plugins
java -jar ~/jenkins-artifacts-bundle/tools/jenkins-plugin-manager-2.15.0.jar \
  --war ~/jenkins-artifacts-bundle/jenkins/jenkins-2.555.3.war \
  --plugin-file ~/jenkins-artifacts-bundle/jenkins/plugins.seed.txt \
  --latest false \
  --plugin-download-directory ~/jenkins-artifacts-bundle/jenkins/plugins \
  > ~/jenkins-artifacts-bundle/jenkins/plugin-download-report.txt
```

Generate and review the full direct-plus-transitive locked plugin closure from
downloaded plugin manifests:

```bash
cd ~/jenkins-artifacts-bundle/jenkins
for plugin in plugins/*.hpi plugins/*.jpi; do
  [ -e "$plugin" ] || continue
  short_name=$(unzip -p "$plugin" META-INF/MANIFEST.MF | tr -d '\r' | awk -F': ' '/^Short-Name:/ {print $2; exit}')
  plugin_version=$(unzip -p "$plugin" META-INF/MANIFEST.MF | tr -d '\r' | awk -F': ' '/^Plugin-Version:/ {print $2; exit}')
  printf '%s:%s\n' "$short_name" "$plugin_version"
done | sort -u > plugins.lock.txt
```

Every `plugins.lock.txt` entry must include `plugin-name:version`. Treat any
blank name, blank version, missing accepted direct plugin, or unexpected full
closure entry as a release-blocking issue.

Preserve resolver evidence for the accepted direct pins and check
update/security metadata for the full lock:

```bash
java -jar ~/jenkins-artifacts-bundle/tools/jenkins-plugin-manager-2.15.0.jar \
  --war ~/jenkins-artifacts-bundle/jenkins/jenkins-2.555.3.war \
  --plugin-file ~/jenkins-artifacts-bundle/jenkins/plugins.seed.txt \
  --latest false \
  --no-download \
  --list \
  > ~/jenkins-artifacts-bundle/jenkins/plugin-resolution-report.txt

java -jar ~/jenkins-artifacts-bundle/tools/jenkins-plugin-manager-2.15.0.jar \
  --war ~/jenkins-artifacts-bundle/jenkins/jenkins-2.555.3.war \
  --plugin-file ~/jenkins-artifacts-bundle/jenkins/plugins.lock.txt \
  --latest false \
  --available-updates \
  --view-all-security-warnings \
  --no-download \
  > ~/jenkins-artifacts-bundle/jenkins/plugin-review-report.txt
```

Review `plugin-resolution-report.txt`, `plugin-review-report.txt`, and
`plugins.lock.txt`, then record approval before moving the bundle into the
offline environment.

Create manifests, checksums, and archive:

```bash
cd ~/jenkins-artifacts-bundle
find jenkins/plugins -type f -printf '%f\n' \
  | sort > jenkins/plugin-artifacts.manifest
printf 'bundle_kind=jenkins-controller-artifacts\njenkins_version=2.555.3\njenkins_core_deb=jenkins_2.555.3_all.deb\njenkins_war=jenkins-2.555.3.war\nplugin_lock=plugins.lock.txt\nplugin_resolution_report=plugin-resolution-report.txt\nplugin_review_report=plugin-review-report.txt\nplugin_artifacts=plugin-artifacts.manifest\n' \
  > jenkins/release-unit.manifest
find . -type f ! -path './checksums/SHA256SUMS' -print0 \
  | sort -z | xargs -0 sha256sum > checksums/SHA256SUMS
tar -czf ~/jenkins-artifacts-bundle.tar.gz -C ~ jenkins-artifacts-bundle
sha256sum ~/jenkins-artifacts-bundle.tar.gz > ~/jenkins-artifacts-bundle.tar.gz.sha256
```

The approved controller release unit is the combination of the artifact
archive, its `.sha256` file, the internal `SHA256SUMS` file,
`plugins.intent.txt`, `plugin-version-proposals.txt`,
`plugin-version-resolution-report.txt`, generated `plugins.seed.txt`,
`plugins.lock.txt`, plugin review reports, `plugin-artifacts.manifest`, and
`release-unit.manifest`.

#### 2.2.2 Install the Controller Artifact Bundle Manually

Transfer the artifact archive and `.sha256` file to the Jenkins host with
approved media or an approved internal transfer path. Run on the Jenkins host:

```bash
cd /home/operator
sha256sum -c jenkins-artifacts-bundle.tar.gz.sha256
sudo rm -rf /opt/jenkins-artifacts-bundle
sudo tar -xzf jenkins-artifacts-bundle.tar.gz -C /opt
cd /opt/jenkins-artifacts-bundle
sha256sum -c checksums/SHA256SUMS
sudo apt install -y /opt/jenkins-artifacts-bundle/jenkins/jenkins_2.555.3_all.deb
sudo apt-mark hold jenkins
java -version
```

Install or refresh controller plugins from the artifact bundle:

```bash
sudo systemctl stop jenkins || true
sudo install -d -o jenkins -g jenkins /var/lib/jenkins/plugins
sudo cp /opt/jenkins-artifacts-bundle/jenkins/plugins/*.{hpi,jpi} /var/lib/jenkins/plugins/ 2>/dev/null || true
sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins
sudo systemctl start jenkins || true
```

For artifact recovery, rerun only the artifact archive checksum, extraction,
Jenkins `.deb` install, package hold, and plugin copy commands. OS package
recovery uses the approved internal Ubuntu/OS package repository path.

## 3. Jenkins Installation

### 3.1 Install Jenkins

```bash
apt update
apt install -y fontconfig openjdk-21-jre
apt install -y jenkins=2.555.3
apt-mark hold jenkins
```

Verify:

```bash
systemctl status jenkins
journalctl -u jenkins -n 100 --no-pager
```

### 3.2 Configure Jenkins Runtime

Create a systemd override:

```bash
systemctl edit jenkins
```

Add:

```ini
[Service]
User=jenkins
Group=jenkins
Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64"
Environment="JENKINS_PORT=8080"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
```

Reload and restart:

```bash
systemctl daemon-reload
chown -R jenkins:jenkins /var/lib/jenkins
systemctl restart jenkins
```

If setup wizard is used instead of JCasC, remove `-Djenkins.install.runSetupWizard=false` until initial setup is complete.

### 3.3 Install Jenkins Plugins

Recommended plugins:

- `gerrit-trigger`: primary event-driven Gerrit integration.
- `gerrit-code-review`: optional alternative for multibranch/Jenkinsfile-style Gerrit workflows.
- `git`
- `workflow-aggregator`
- `pipeline-groovy-lib`
- `pipeline-stage-view`
- `credentials`
- `ssh-credentials`
- `credentials-binding`
- `matrix-auth` or `role-strategy`
- `configuration-as-code`
- `job-dsl`
- `timestamper`
- `ws-cleanup`
- `build-timeout`
- `lockable-resources`
- `mailer` or `email-ext`
- `prometheus`
- `metrics`

Plugin download and resolution belong to the bundle-factory workflow in section
2.2.1. The Jenkins controller host installs only reviewed plugin artifacts from
the staged controller artifact bundle.

Install staged plugin artifacts:

```bash
systemctl stop jenkins
install -d -o jenkins -g jenkins /var/lib/jenkins/plugins
cp /opt/jenkins-artifacts-bundle/jenkins/plugins/*.{hpi,jpi} /var/lib/jenkins/plugins/ 2>/dev/null || true
chown -R jenkins:jenkins /var/lib/jenkins/plugins
systemctl start jenkins
```

## 4. Jenkins Configuration

### 4.1 Configuration as Code Baseline

Create `/var/lib/jenkins/casc/jenkins.yaml`:

```yaml
jenkins:
  systemMessage: "Production Jenkins controller for Gerrit CI"
  numExecutors: 0
  securityRealm:
    ldap:
      configurations:
        - server: "ldap://LDAP_HOST:389"
          rootDN: "LDAP_ROOT_DN"
          managerDN: "LDAP_BIND_DN"
          managerPasswordSecret: "${LDAP_BIND_PASSWORD}"
          userSearchBase: "LDAP_USER_BASE"
          userSearch: "uid={0}"
          groupSearchBase: "LDAP_GROUP_BASE"
  authorizationStrategy:
    globalMatrix:
      entries:
        - group:
            name: "jenkins-admins"
            permissions:
              - "Overall/Administer"
        - group:
            name: "authenticated"
            permissions:
              - "Overall/Read"
              - "Job/Read"
        - group:
            name: "gerrit-ci-users"
            permissions:
              - "Job/Build"

unclassified:
  location:
    url: "http://JENKINS_HOST:8080/"
  prometheusConfiguration:
    collectDiskUsage: false
    collectingMetricsPeriodInSeconds: 1800
```

Set the Jenkins location URL to the URL users enter in their browser. In
production behind a reverse proxy or load balancer, this should normally be the
external HTTPS URL, for example `https://jenkins.example.internal/`, even when
Jenkins listens internally on plain HTTP.

If `rootDN` is set, `userSearchBase` and `groupSearchBase` should normally be relative to that root, for example `ou=people` and `ou=groups`. If your organization provides absolute base DNs such as `ou=people,dc=example,dc=internal`, either remove `rootDN` or convert the search bases to relative values. Mixing `rootDN` with absolute search bases can make LDAP searches target the wrong DN.

Store secrets in an environment file readable only by root:

```bash
cat > /etc/jenkins-casc.env <<'EOF'
LDAP_BIND_PASSWORD=REPLACE_WITH_SECRET
COLLECTING_METRICS_PERIOD_IN_SECONDS=1800
EOF
chmod 0600 /etc/jenkins-casc.env
chown root:root /etc/jenkins-casc.env
```

Update the systemd override:

```ini
[Service]
EnvironmentFile=/etc/jenkins-casc.env
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc/jenkins.yaml"
```

Apply:

```bash
chown -R jenkins:jenkins /var/lib/jenkins/casc
systemctl daemon-reload
systemctl restart jenkins
```

### 4.2 Outbound SSH Build Agent

Do not run builds on the Jenkins controller. Keep the built-in node at zero
executors and provide build capacity through agents. This deployment uses
Jenkins' SSH launcher: the controller connects out to the build server over
SSH. It is not an inbound/remoting agent setup.

Prepare the build server, agent artifacts, SSH account, and recovery steps
with `jenkins-agent-native-operations-reference.md`. Controller-only bringup
stops before node registration, smoke-job scheduling, Gerrit Trigger live
connection, and `Verified` voting. These values are inventory inputs for the
later shared integration workflow, not controller-only validation
requirements. Perform the cross-role operations only after the Jenkins
controller and agent host are both ready.

Agent endpoint inventory, credential creation, public-key handoff, executor
counts, labels, scheduling, and node registration belong to the later shared
integration workflow, not this controller role-local native reference. The
Jenkins controller owns the private key; the agent host consumes only the
matching public key during that later workflow.

### 4.3 UI-Driven Fallback

If not using JCasC:

1. Browse to `http://JENKINS_HOST:8080/`.
2. Use the initial admin password:

   ```bash
   cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

3. Install the recommended plugins plus Gerrit integration plugins.
4. Configure LDAP under `Manage Jenkins` > `Security`.
5. Configure authorization with `matrix-auth` or `role-strategy`.
6. Defer the `jenkins-gerrit` Gerrit integration account SSH key until the
   later shared integration workflow.
7. Defer Gerrit Trigger configuration until the later shared integration
   workflow.

## 5. Shared Integration Handoff

Controller-only bringup stops before cross-role Gerrit and agent integration.
The Jenkins controller role proves Jenkins startup, HTTP reachability,
curated plugin installation, LDAP/JCasC configuration, zero built-in
executors, runtime configuration, staged artifacts, bounded logs, and
role-local evidence. It does not generate integration keypairs, configure
Gerrit Trigger, register an SSH agent node, prove stream-events, run agent
scheduling checks, or prove a `Verified` vote.

Later cross-role work belongs to the separate integration workflow, not this
controller role-local native reference. That later workflow owns
Jenkins-to-Gerrit SSH setup, Jenkins-to-agent SSH setup, Gerrit Trigger
configuration, integration validation, trigger verification, and integration
evidence. Until that workflow is implemented, this native reference remains
limited to Jenkins controller role-local readiness.

Credential custody remains fixed:

- The Jenkins controller owns the Jenkins-to-Gerrit private key.
- The Jenkins controller owns the Jenkins-to-agent private key.
- Gerrit and the Jenkins agent consume only matching public keys.
- Controller role-local evidence may record public key fingerprints, accounts,
  endpoints, bounded log paths, and redaction status.
- Controller role-local and integration evidence must not contain private
  keys, passwords, tokens, LDAP bind secrets, or full secret-bearing env
  values.

## 6. Controller-Only Validation

Run:

```bash
java -version
systemctl is-enabled jenkins
systemctl is-active jenkins
curl -I http://JENKINS_HOST:8080/
journalctl -u jenkins -n 100 --no-pager
```

Acceptance checks:

- OpenJDK 21 is active.
- Jenkins starts under systemd.
- Jenkins survives reboot.
- LDAP users can log in.
- Required plugins load successfully.
- Gerrit SSH, Gerrit event streaming, Jenkins agent scheduling, and `Verified`
  vote checks are deferred to the later shared integration workflow.
- Do not accept rendered Gerrit Trigger config, keypairs, node registration,
  scheduling records, or trigger/vote proof as controller-only validation
  evidence.

## 7. Backup and Operations

Back up:

- `/var/lib/jenkins/config.xml`
- `/var/lib/jenkins/jobs`
- `/var/lib/jenkins/plugins`
- `/var/lib/jenkins/users`
- `/var/lib/jenkins/credentials.xml`
- `/var/lib/jenkins/secrets`
- `/var/lib/jenkins/casc`
- `/etc/jenkins-casc.env`

Example:

```bash
rsync -aH --numeric-ids /var/lib/jenkins/ BACKUP_HOST:/backups/jenkins/
```

Protect `/var/lib/jenkins/secrets` and `/etc/jenkins-casc.env`; losing them can break credential decryption or service authentication.

Upgrade principles:

- Pin Jenkins core and plugin versions together.
- Back up before every upgrade.
- Test upgrades in staging before production.
- Upgrade Jenkins LTS first, then plugins compatible with that LTS.
- Do not mix latest plugins with an older pinned Jenkins controller unless plugin requirements have been checked.
- Rebuild the Jenkins controller artifact bundle and record checksums for every
  approved application artifact upgrade.

## 8. References

- Jenkins agent native operations:
  `jenkins-agent-native-operations-reference.md`
- Jenkins Linux installation: https://www.jenkins.io/doc/book/installing/linux/
- Jenkins Java support policy: https://www.jenkins.io/doc/book/platform-information/support-policy-java/
- Jenkins offline installation: https://www.jenkins.io/doc/book/installing/offline/
- Jenkins Plugin Installation Manager Tool: https://github.com/jenkinsci/plugin-installation-manager-tool
- Jenkins Gerrit Trigger plugin: https://plugins.jenkins.io/gerrit-trigger/
- Jenkins Gerrit Code Review plugin: https://plugins.jenkins.io/gerrit-code-review/
- Jenkins stable Debian package metadata: https://pkg.jenkins.io/debian-stable/binary/Packages
- Jenkins stable update center: https://updates.jenkins.io/stable/update-center.actual.json
