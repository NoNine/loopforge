# Jenkins Controller Native Operations Reference

This document is the manual target-deployment native operations reference for
the Jenkins controller. It uses OS and application-native operations only, not
repository automation commands.

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

Use this controller manual with `docs/operations/native/jenkins-agent.md`
when the deployment includes outbound SSH build agents. Use
`docs/operations/native/integration.md` after controller-only readiness is
proven. This document covers controller-only bringup through Jenkins runtime,
LDAP/JCasC, plugin, service, and endpoint readiness. Gerrit Trigger setup,
Jenkins-to-Gerrit keys, controller node registration, scheduling proof, and
`Verified` vote proof are later integration-step work.

Assumptions:

- Jenkins runs on its own Ubuntu 24.04 LTS host.
- Gerrit runs on a separate host and is reachable from Jenkins.
- Identity is integrated with LDAP/Active Directory.
- Jenkins exposes a direct service port on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Jenkins controller application artifacts.
- Production host commands are run by the operator account with `sudo` or
  equivalent delegated administrator privileges unless noted. Do not use
  `root` as a Loopforge account or direct login identity.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, Jenkins controller
`2.555.3 LTS`, and Jenkins Plugin Installation Manager Tool `2.15.0`.
`docs/baselines/version-baseline.md` owns the package-wide baseline and reviewed update
rules.

Production warning: direct HTTP service ports are documented because that is the selected deployment model. For production environments outside a trusted network, terminate TLS with a reverse proxy or enterprise load balancer before exposing Jenkins to users.

Privilege warning: a production Jenkins install cannot be completed by an
unprivileged user alone. Package installation, `/etc`, `/opt`,
`/var/lib/jenkins`, file ownership, systemd overrides, service restarts, and
protected system secret files require delegated administrator privilege from
the operator account. Root may own OS-reserved files, but root is not a
Loopforge account, runtime identity, or supported direct login identity.

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

- Install OS packages and Java dependencies.
- Confirm the local Jenkins runtime account and group exist on the Jenkins host.
- Create and own `/var/lib/jenkins`, `/var/lib/jenkins/war`,
  `/var/lib/jenkins/plugins`, `/var/lib/jenkins/jcasc`, and any staged
  `/var/lib/loopforge/staging/jenkins` content as documented.
- Create the Jenkins systemd service, reload systemd, and start, stop, restart,
  or enable Jenkins.
- Run any `chown`, `chmod`, `apt`, `dpkg`, `systemctl`, or writes under `/etc`, `/opt`, or `/var/lib`.

A home-directory Jenkins process can be useful for lab validation, but it is not this production deployment. It will not match the documented package lifecycle, systemd service management, ownership model, backup paths, or secret handling.

## 2. Dependencies And Jenkins Controller Artifact Bundle

### 2.1 Ubuntu Dependencies

The package rationale and layered classification are maintained in
`docs/baselines/package-requirements.md`.

Run on the Jenkins host:

```bash
apt update
apt install -y \
  ca-certificates \
  curl \
  fontconfig \
  nfs-common \
  openjdk-21-jre \
  openssh-client \
  rsync \
  tar \
  wget
java -version
```

The Jenkins controller application is staged as a reviewed WAR artifact in the
Jenkins artifact bundle. Do not configure a public Jenkins apt repository on the
target host for v1.

### 2.2 Jenkins Controller Artifact Bundle

v1 does not support installing OS dependencies from locally bundled Ubuntu
packages. Use approved internal Ubuntu/OS package repositories for OS packages
on target hosts.

Prepare Jenkins controller application artifacts in staging or a bundle-factory
environment, then stage only the reviewed application artifact archive to the
Jenkins controller host.

Official source references:

```text
https://get.jenkins.io/war-stable/2.555.3/jenkins.war
https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar
https://updates.jenkins.io/download/plugins
```

#### 2.2.1 Create the Controller Artifact Bundle

Run on the bundle-factory VM:

```bash
mkdir -p ~/jenkins-artifacts-bundle/{jenkins/plugins,tools}
cd ~/jenkins-artifacts-bundle/jenkins
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

Record the accepted direct plugin pins in a temporary Plugin Installation
Manager input file. These pins come from the reviewed deployment input; do not
add transitive dependencies to this file.

```bash
tmp_plugins_seed=$(mktemp)
cat > "$tmp_plugins_seed" <<'EOF'
<accepted-direct-plugin>:<accepted-version>
EOF
```

Resolve and download the accepted direct pins and their dependencies once.
Plugin Installation Manager output is bounded operator log evidence, not a
bundle proof file.

```bash
rm -rf ~/jenkins-artifacts-bundle/jenkins/plugins
mkdir -p ~/jenkins-artifacts-bundle/jenkins/plugins
java -jar ~/jenkins-artifacts-bundle/tools/jenkins-plugin-manager-2.15.0.jar \
  --war ~/jenkins-artifacts-bundle/jenkins/jenkins-2.555.3.war \
  --plugin-file "$tmp_plugins_seed" \
  --plugin-download-directory ~/jenkins-artifacts-bundle/jenkins/plugins
```

Validate the actual resolved plugin artifacts by reading their Jenkins plugin
manifests. Treat any blank name, blank version, missing accepted direct plugin,
or direct plugin version drift as release-blocking.

```bash
cd ~/jenkins-artifacts-bundle/jenkins
for plugin in plugins/*.hpi plugins/*.jpi; do
  [ -e "$plugin" ] || continue
  manifest=$(unzip -p "$plugin" META-INF/MANIFEST.MF | tr -d '\r')
  short_name=$(printf '%s\n' "$manifest" | awk -F': ' '/^Short-Name:/ {print $2; exit}')
  plugin_version=$(printf '%s\n' "$manifest" | awk -F': ' '/^Plugin-Version:/ {print $2; exit}')
  test -n "$short_name"
  test -n "$plugin_version"
  printf '%s:%s\n' "$short_name" "$plugin_version"
done | sort -u > /tmp/jenkins-plugin-facts.txt
```

Compare `/tmp/jenkins-plugin-facts.txt` with the reviewed direct pins and stop
if any accepted direct pin is absent or has a different version.

Create manifests, checksums, and archive:

```bash
cd ~/jenkins-artifacts-bundle
cat > jenkins/manifest.txt <<'EOF'
harness_manifest_version=1
role=jenkins-controller
bundle_name=jenkins-artifacts-bundle
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=not-applicable
jenkins_version=2.555.3
jenkins_plugin_manager_version=2.15.0
resolved_plugin_count=<count-of-resolved-plugin-artifacts>
war=jenkins-2.555.3.war
plugin_manager=jenkins-plugin-manager-2.15.0.jar
template_count=2
EOF
(cd jenkins && find . -type f ! -name checksums.sha256 -print0 \
  | sort -z | xargs -0 sha256sum > checksums.sha256)
tar -czf ~/jenkins-artifacts-bundle.tar.gz -C ~/jenkins-artifacts-bundle jenkins
sha256sum ~/jenkins-artifacts-bundle.tar.gz > ~/jenkins-artifacts-bundle.tar.gz.sha256
```

The approved controller release unit is the artifact archive, its `.sha256`
file, and the staged Jenkins WAR, Plugin Installation Manager, plugin
artifacts, and controller templates.

#### 2.2.2 Install the Controller Artifact Bundle Manually

Transfer the artifact archive and `.sha256` file to the Jenkins host with
approved media or an approved internal transfer path. Run on the Jenkins host:

```bash
operator_account="${LOOPFORGE_OPERATOR_ACCOUNT:-ci-operator}"
operator_group="${LOOPFORGE_OPERATOR_GROUP:-$operator_account}"
operator_home="$(getent passwd "$operator_account" | cut -d: -f6)"
[ -n "$operator_home" ] || {
  printf 'missing operator account: %s\n' "$operator_account" >&2
  exit 1
}

cd "$operator_home"
sha256sum -c jenkins-artifacts-bundle.tar.gz.sha256
sudo install -d -m 0750 -o "$operator_account" -g "$operator_group" /var/lib/loopforge/staging
sudo rm -rf /var/lib/loopforge/staging/jenkins
sudo tar -xzf jenkins-artifacts-bundle.tar.gz -C /var/lib/loopforge/staging
sudo chown -R "$operator_account:$operator_group" /var/lib/loopforge/staging/jenkins
cd /var/lib/loopforge/staging/jenkins
sha256sum -c checksums.sha256
java -version
```

Install or refresh controller application artifacts from the artifact bundle:

```bash
sudo systemctl stop jenkins || true
sudo groupadd --gid 61020 jenkins || true
sudo useradd --uid 61020 --gid 61020 --home-dir /var/lib/jenkins --shell /bin/bash jenkins || true
sudo install -d -o jenkins -g jenkins -m 0755 /var/lib/jenkins/war
sudo cp /var/lib/loopforge/staging/jenkins/jenkins-2.555.3.war /var/lib/jenkins/war/jenkins.war
sudo cp /var/lib/loopforge/staging/jenkins/jenkins-plugin-manager-2.15.0.jar /var/lib/jenkins/war/jenkins-plugin-manager.jar
sudo install -d -o jenkins -g jenkins /var/lib/jenkins/plugins
sudo cp /var/lib/loopforge/staging/jenkins/plugins/*.{hpi,jpi} /var/lib/jenkins/plugins/ 2>/dev/null || true
sudo install -d -o jenkins -g jenkins /var/lib/jenkins/templates
sudo cp -R /var/lib/loopforge/staging/jenkins/templates/. /var/lib/jenkins/templates/
sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins
sudo chown -R jenkins:jenkins /var/lib/jenkins/war /var/lib/jenkins/templates
```

For artifact recovery, rerun only the artifact archive checksum, extraction,
WAR, Plugin Installation Manager, template, and plugin copy commands.
OS package recovery uses the approved internal Ubuntu/OS package repository
path.

## 3. Jenkins Installation

### 3.1 Install Jenkins

Install Jenkins controller application artifacts from the staged controller
artifact bundle as shown in Section 2.2. Do not configure a public Jenkins apt
repository on the target host for v1.

Verify:

```bash
test -s /var/lib/jenkins/war/jenkins.war
test -s /var/lib/jenkins/war/jenkins-plugin-manager.jar
test -s /var/lib/jenkins/war/jenkins.war
```

### 3.2 Configure Jenkins Runtime

Create `/etc/systemd/system/jenkins.service`:

```ini
[Unit]
Description=Jenkins Controller
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=jenkins
Group=jenkins
Environment=JENKINS_HOME=/var/lib/jenkins
Environment=CASC_JENKINS_CONFIG=/var/lib/jenkins/jcasc/jenkins.yaml
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
ExecStart=/usr/bin/java $JAVA_OPTS -jar /var/lib/jenkins/war/jenkins.war --httpPort=8080 --webroot=/var/lib/jenkins/war-cache
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

Reload and start:

```bash
systemctl daemon-reload
chown -R jenkins:jenkins /var/lib/jenkins
systemctl enable --now jenkins
systemctl status jenkins
journalctl -u jenkins -n 100 --no-pager
```

If setup wizard is used instead of JCasC, remove `-Djenkins.install.runSetupWizard=false` until initial setup is complete.

After plugin and JCasC changes, restart Jenkins explicitly through systemd.
Validation observes the enabled and active unit, its runtime owner, endpoints,
LDAP/JCasC, and bounded logs; it does not start or repair Jenkins.

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
systemctl stop jenkins || true
install -d -o jenkins -g jenkins /var/lib/jenkins/plugins
cp /var/lib/loopforge/staging/jenkins/plugins/*.{hpi,jpi} /var/lib/jenkins/plugins/ 2>/dev/null || true
chown -R jenkins:jenkins /var/lib/jenkins/plugins
systemctl start jenkins
```

## 4. Jenkins Configuration

### 4.1 Configuration as Code Baseline

Create `/var/lib/jenkins/jcasc/jenkins.yaml`:

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

Protect the JCasC file because it contains the reviewed LDAP bind password:

```bash
chown -R jenkins:jenkins /var/lib/jenkins/jcasc
chmod 0700 /var/lib/jenkins/jcasc
chmod 0600 /var/lib/jenkins/jcasc/jenkins.yaml
```

Ensure the systemd service exports the JCasC path:

```ini
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/jcasc/jenkins.yaml"
```

Apply:

```bash
systemctl daemon-reload
systemctl restart jenkins
```

### 4.2 Outbound SSH Build Agent

Do not run builds on the Jenkins controller. Keep the built-in node at zero
executors and provide build capacity through agents. This deployment uses
Jenkins' SSH launcher: the controller connects out to the build server over
SSH. It is not an inbound/remoting agent setup.

Prepare the build server, agent artifacts, SSH account, and recovery steps
with `docs/operations/native/jenkins-agent.md`. Controller-only bringup
stops before node registration, smoke-job scheduling, Gerrit Trigger live
connection, and `Verified` voting. These values are inventory inputs for the
integration native operations reference, not controller-only validation
requirements. Perform the cross-role operations only after the Jenkins
controller and agent host are both ready.

Agent endpoint inventory, credential creation, public-key handoff, node name,
executor counts, scheduling labels, scheduling, and node registration belong to
`docs/operations/native/integration.md`, not this controller role-local
native reference. The Jenkins controller owns the private key; the agent host
consumes only the matching public key during that later workflow.

### 4.3 UI-Driven Fallback

If not using JCasC:

1. Browse to `http://JENKINS_HOST:8080/`.
2. Use the initial admin password:

   ```bash
   cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

3. Install the recommended plugins plus the reviewed Gerrit integration
   plugins from `Manage Jenkins` > `Plugins`.
4. Open `Manage Jenkins` > `Security`, select LDAP as the security realm, and
   enter the reviewed LDAP URL, user search base, group search base, manager DN,
   and bind secret according to site policy.
5. Configure authorization with `matrix-auth` or `role-strategy` from the same
   `Security` page, granting administrator access only to the reviewed Jenkins
   administrator group.
6. Open `Manage Jenkins` > `System` and set the Jenkins URL to the reviewed
   browser URL users enter, normally `JENKINS_URL`.
7. Open `Manage Jenkins` > `Nodes` > built-in node or `Configure System`,
   depending on the installed UI, and keep the built-in node executor count at
   zero.
8. Open `Manage Jenkins` > `Plugins` > `Installed plugins` and confirm the
   required plugins are enabled without load errors.
9. Defer the `jenkins-gerrit` Gerrit integration account SSH key until
   integration-native operations.
10. Defer Gerrit Trigger configuration until integration-native operations.

## 5. Shared Integration Handoff

Controller-only bringup stops before cross-role Gerrit and agent integration.
The Jenkins controller role proves Jenkins startup, HTTP reachability,
curated plugin installation, LDAP/JCasC configuration, zero built-in
executors, runtime configuration, staged artifacts, bounded logs, and
role-local evidence. It does not generate integration keypairs, configure
Gerrit Trigger, register an SSH agent node, prove stream-events, run agent
scheduling checks, or prove a `Verified` vote.

Later cross-role work belongs to `docs/operations/native/integration.md`,
not this controller role-local native reference. That later workflow owns
Jenkins-to-Gerrit SSH setup, Jenkins-to-agent SSH setup, Gerrit Trigger
configuration, integration validation, trigger verification, and integration
acceptance. The manual integration workflow is available; this native
reference remains limited to Jenkins controller role-local readiness.

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
  vote checks are deferred to `docs/operations/native/integration.md`.
- Do not accept rendered Gerrit Trigger config, keypairs, node registration,
  scheduling records, or trigger/vote proof as controller-only validation
  evidence.

Use the Jenkins Web UI to complete the application checks:

1. Browse to `JENKINS_URL` and sign in as the reviewed Jenkins administrator.
2. Open `Manage Jenkins` and confirm no administrative monitor reports a plugin
   load failure for required plugins.
3. Open `Manage Jenkins` > `Security` and confirm LDAP and authorization
   settings match the reviewed values without exposing bind secrets in
   evidence.
4. Open `Manage Jenkins` > `Nodes` and confirm the built-in node has zero
   executors.

## 7. Backup and Operations

Back up:

- `/var/lib/jenkins/config.xml`
- `/var/lib/jenkins/jobs`
- `/var/lib/jenkins/plugins`
- `/var/lib/jenkins/users`
- `/var/lib/jenkins/credentials.xml`
- `/var/lib/jenkins/secrets`
- `/var/lib/jenkins/jcasc`

Example:

```bash
rsync -aH --numeric-ids /var/lib/jenkins/ BACKUP_HOST:/backups/jenkins/
```

Protect `/var/lib/jenkins/secrets` and `/var/lib/jenkins/jcasc`; losing them can break credential decryption or service authentication.

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
  `docs/operations/native/jenkins-agent.md`
- Integration native operations:
  `docs/operations/native/integration.md`
- Jenkins Linux installation: https://www.jenkins.io/doc/book/installing/linux/
- Jenkins Java support policy: https://www.jenkins.io/doc/book/platform-information/support-policy-java/
- Jenkins offline installation: https://www.jenkins.io/doc/book/installing/offline/
- Jenkins Plugin Installation Manager Tool: https://github.com/jenkinsci/plugin-installation-manager-tool
- Jenkins Gerrit Trigger plugin: https://plugins.jenkins.io/gerrit-trigger/
- Jenkins Gerrit Code Review plugin: https://plugins.jenkins.io/gerrit-code-review/
- Jenkins stable Debian package metadata: https://pkg.jenkins.io/debian-stable/binary/Packages
- Jenkins stable update center: https://updates.jenkins.io/stable/update-center.actual.json
