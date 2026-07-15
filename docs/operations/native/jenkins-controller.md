# Jenkins Controller Native Operations Reference

This document is the manual target-deployment native operations reference for
the Jenkins controller. It uses OS and application-native operations only, not
repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Public internet fallback on target hosts is simulation-only and must be labeled
as such in docs, logs, and verification summaries.

Jenkins controller application artifact bundles are key-free. They contain
reviewed Jenkins application files, plugin artifacts, and checksums, but not
SSH private keys, public keys, `authorized_keys`, or generated public-key
handoff files.
Jenkins-to-Gerrit and Jenkins-to-agent keypair generation and public-key
handoff are integration operations after controller role-local readiness is
proven.


Audience: production operators installing Jenkins on Ubuntu 24.04 LTS without Docker.

Use this controller manual with `docs/operations/native/jenkins-agent.md`
when the deployment includes outbound SSH build agents. Use
`docs/operations/native/integration.md` after controller-only readiness is
proven. This document covers controller-only bringup through Jenkins runtime,
LDAP/JCasC, plugin, service, and endpoint readiness. Gerrit Trigger setup,
Jenkins-to-Gerrit keys, Jenkins agent node registration, scheduling proof,
and `Verified` vote proof are later integration-step work.

Assumptions:

- Jenkins runs on its own Ubuntu 24.04 LTS host.
- The target is freshly provisioned with no prior Jenkins or Loopforge runtime
  state, including no Jenkins runtime account, group, or `/var/lib/jenkins`
  path.
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
| Jenkins browser URL | `JENKINS_URL`, reviewed browser-visible root URL |
| HTTP port | `JENKINS_HTTP_PORT`, default `8080` |
| LDAP URL | `LDAP_URL`, for example `ldap://LDAP_HOST:389` or `ldaps://LDAP_HOST:636` |
| LDAP root DN | `LDAP_ROOT_DN`, or empty when using absolute search bases |
| LDAP bind DN | `uid=jenkins-ldap-bind,LDAP_USER_BASE` or provided bind DN |
| LDAP user base | `LDAP_USER_BASE` |
| LDAP group base | `LDAP_GROUP_BASE` |
| LDAP Jenkins administrator | `LDAP_ADMIN_USER`, reviewed site-specific LDAP user |
| Network mode | Approved internal OS repositories for target-host OS dependencies |
| Operator account | `LOOPFORGE_OPERATOR_ACCOUNT`, default `ci-operator` |
| Operator group | `LOOPFORGE_OPERATOR_GROUP`, default `ci-operator` |
| Jenkins runtime user | `jenkins`, local OS account |
| Jenkins runtime group | `jenkins`, local OS group |
| Jenkins runtime UID | `JENKINS_RUNTIME_UID`, default `61020` |
| Jenkins runtime GID | `JENKINS_RUNTIME_GID`, default `61020` |
| Jenkins home | `/var/lib/jenkins`, owned by `jenkins:jenkins` |

Run on the Jenkins host:

```bash
cat /etc/os-release
hostnamectl
timedatectl
df -h /var/lib
free -h
systemctl --failed
getent hosts JENKINS_HOST
```

Confirm `/etc/os-release` reports Ubuntu `24.04` and `noble`, the hostname and
time settings match reviewed inventory, `/var/lib` has sufficient capacity,
and any failed systemd units have an approved disposition. The final command
must resolve `JENKINS_HOST`; stop and correct host identity before continuing
if it does not.

Use port `389` for LDAP with StartTLS if required. Use port `636` for LDAPS.

The Jenkins runtime user and group are reviewed local OS identities. This
clean-install procedure creates them during installation. If your site uses
different values, substitute the reviewed name and numeric identity everywhere
this manual shows the defaults.

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
- Confirm the reviewed Jenkins runtime account/group names, UID/GID, and
  product home are unused on the freshly provisioned host, then create them.
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
sudo apt update
sudo apt install -y \
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
test ! -e "$HOME/jenkins-artifacts-bundle"
test ! -e "$HOME/jenkins-artifacts-bundle.tar.gz"
test ! -e "$HOME/jenkins-artifacts-bundle.tar.gz.sha256"
mkdir -p "$HOME/jenkins-artifacts-bundle/jenkins"
cd "$HOME/jenkins-artifacts-bundle/jenkins"
wget -O jenkins-2.555.3.war \
  https://get.jenkins.io/war-stable/2.555.3/jenkins.war
cat > plugins.intent.txt <<'EOF'
configuration-as-code:2100.vb_fd699d2a_09c
credentials:1506.v948b_b_b_7dec44
git:5.10.1
gerrit-trigger:3.1983.v57096fe9923c
ldap:807.809.vd3a_4e5e4ec98
matrix-auth:3.2.10
ssh-credentials:372.va_250881b_08cd
ssh-slaves:3.1097.v868116049892
workflow-aggregator:608.v67378e9d3db_1
job-dsl:3654.vdf58f53e2d15
timestamper:1.30
ws-cleanup:0.49
EOF
```

The freshness test must succeed. Stop and select a new bundle path if the
reviewed path already exists; do not delete or reuse an earlier bundle.

`plugins.intent.txt` is the operator-owned direct plugin intent from the v1
version baseline. Each line is an exact `name:version` pin. Do not add
transitive dependencies to this file only because they appear in Plugin
Installation Manager resolver output.

Download and verify the Jenkins Plugin Installation Manager Tool:

```bash
cd ~/jenkins-artifacts-bundle/jenkins
wget https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar
wget https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar.sha256
sha256sum jenkins-plugin-manager-2.15.0.jar
cat jenkins-plugin-manager-2.15.0.jar.sha256
```

The two displayed 64-character hashes must match exactly. Stop if they differ.

Resolve and download the accepted direct pins and their dependencies once.
Plugin Installation Manager validates its input, compatibility, dependency
resolution, and downloads. Do not use `--skip-failed-plugins`; stop if this
command fails.

```bash
mkdir ~/jenkins-artifacts-bundle/jenkins/plugins
java -jar ~/jenkins-artifacts-bundle/jenkins/jenkins-plugin-manager-2.15.0.jar \
  --war ~/jenkins-artifacts-bundle/jenkins/jenkins-2.555.3.war \
  --plugin-file ~/jenkins-artifacts-bundle/jenkins/plugins.intent.txt \
  --plugin-download-directory ~/jenkins-artifacts-bundle/jenkins/plugins \
  --list \
  > ~/jenkins-artifacts-bundle/jenkins/plugins.resolved.txt
```

Review the `Resulting plugin list` in `plugins.resolved.txt`. Confirm every
entry in `plugins.intent.txt` appears at its accepted version and stop if any
direct pin is missing or changed. The report also records resolved transitive
dependencies for the change review.

Create checksums and archive:

```bash
cd ~/jenkins-artifacts-bundle
(cd jenkins && find . -type f ! -name checksums.sha256 -print0 \
  | sort -z | xargs -0 sha256sum > checksums.sha256)
tar -czf ~/jenkins-artifacts-bundle.tar.gz -C ~/jenkins-artifacts-bundle jenkins
sha256sum ~/jenkins-artifacts-bundle.tar.gz > ~/jenkins-artifacts-bundle.tar.gz.sha256
```

The approved controller release unit is the artifact archive, its `.sha256`
file, and the staged Jenkins WAR, Plugin Installation Manager, plugin
artifacts, direct plugin intent, resolved plugin inventory, and payload
checksums.

Before transfer, record `plugins.intent.txt`, `plugins.resolved.txt`, and the
approved archive checksum in the deployment change/ticket.

#### 2.2.2 Stage and Verify the Controller Artifact Bundle

Transfer the artifact archive and `.sha256` file to the operator's home on the
Jenkins host with approved media or an approved internal transfer path.
Replace the uppercase operator placeholders below with their reviewed values,
then run each command separately:

```bash
getent passwd LOOPFORGE_OPERATOR_ACCOUNT
getent group LOOPFORGE_OPERATOR_GROUP
cd "$HOME"
sha256sum -c jenkins-artifacts-bundle.tar.gz.sha256
sudo test ! -e /var/lib/loopforge/staging/jenkins
sudo install -d -m 0750 \
  -o LOOPFORGE_OPERATOR_ACCOUNT \
  -g LOOPFORGE_OPERATOR_GROUP \
  /var/lib/loopforge/staging
sudo tar -xzf jenkins-artifacts-bundle.tar.gz \
  -C /var/lib/loopforge/staging
sudo chown -R \
  LOOPFORGE_OPERATOR_ACCOUNT:LOOPFORGE_OPERATOR_GROUP \
  /var/lib/loopforge/staging/jenkins
cd /var/lib/loopforge/staging/jenkins
sha256sum -c checksums.sha256
```

The account and group lookups must return the reviewed operator identities,
both checksum commands must pass, and the staging freshness test must succeed.
Stop and reprovision the clean target if the Jenkins staging path already
exists; do not delete or repair it within this procedure. Staging does not
create the Jenkins runtime identity or change service state.

## 3. Jenkins Installation and First Startup

### 3.1 Create the Runtime Identity and Install Application Artifacts

This is a clean-install procedure. The four `getent` commands below must
return no entry, and the final `test` must succeed. If any reviewed name,
numeric ID, or path is already in use, stop and reprovision the target instead
of adapting or repairing it in place.

```bash
getent passwd jenkins
getent group jenkins
getent passwd 61020
getent group 61020
test ! -e /var/lib/jenkins
```

Create the runtime identity and install the Jenkins application artifacts. Do
not configure a public Jenkins apt repository on the target host for v1.

```bash
sudo groupadd --gid 61020 jenkins
sudo useradd --uid 61020 --gid 61020 --home-dir /var/lib/jenkins --no-create-home --shell /bin/bash jenkins
sudo install -d -m 0755 -o jenkins -g jenkins /var/lib/jenkins
sudo install -d -m 0755 -o jenkins -g jenkins /var/lib/jenkins/war
sudo install -m 0644 -o jenkins -g jenkins \
  /var/lib/loopforge/staging/jenkins/jenkins-2.555.3.war \
  /var/lib/jenkins/war/jenkins.war
test -s /var/lib/jenkins/war/jenkins.war
```

For artifact recovery, rerun the archive and payload checksum checks before
reinstalling the WAR. The Plugin Installation Manager remains a bundle-factory
tool in the staged release unit; Jenkins does not consume it at runtime. OS
package recovery uses the approved internal Ubuntu/OS package repository path.

### 3.2 Configure the Jenkins systemd Unit

Create `/etc/systemd/system/jenkins.service` with `sudoedit` using this unit.
Replace every uppercase placeholder with its reviewed value before saving:

```bash
sudoedit /etc/systemd/system/jenkins.service
```

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
ExecStart=/usr/bin/java $JAVA_OPTS -jar /var/lib/jenkins/war/jenkins.war --httpPort=JENKINS_HTTP_PORT --webroot=/var/lib/jenkins/war-cache
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

Reload and enable the unit without starting Jenkins:

```bash
sudo systemctl daemon-reload
sudo systemctl enable jenkins
systemctl is-enabled jenkins
```

Jenkins remains stopped until the plugin and selected configuration steps are
complete.

### 3.3 Install Jenkins Plugins

The direct plugin set is the reviewed version baseline recorded in
`plugins.intent.txt`. `plugins.resolved.txt` records the direct and transitive
set produced by Plugin Installation Manager. Install that staged `.jpi` set
once, before first startup:

```bash
sudo install -d -m 0755 -o jenkins -g jenkins /var/lib/jenkins/plugins
sudo install -m 0644 -o jenkins -g jenkins \
  /var/lib/loopforge/staging/jenkins/plugins/*.jpi \
  /var/lib/jenkins/plugins/
ls -1 /var/lib/jenkins/plugins/*.jpi
```

The `install` command fails when the staged bundle has no `.jpi` artifacts. Do
not continue with an empty or partial plugin directory.

### 3.4 Configure the JCasC Baseline

JCasC is the default configuration path. To use the UI-driven fallback instead,
remove the `CASC_JENKINS_CONFIG` environment line and the
`-Djenkins.install.runSetupWizard=false` option from the systemd unit with
`sudoedit`, run `sudo systemctl daemon-reload`, skip the remainder of this
section, and continue with Sections 3.5 and 4.

For the default path, create the protected directory, then create
`/var/lib/jenkins/jcasc/jenkins.yaml` with `sudoedit` using the following shape.
Replace every uppercase placeholder, including `${LDAP_BIND_PASSWORD}`, with
its reviewed value before saving.

```bash
sudo install -d -m 0700 -o jenkins -g jenkins /var/lib/jenkins/jcasc
sudoedit /var/lib/jenkins/jcasc/jenkins.yaml
```

```yaml
jenkins:
  systemMessage: "Production Jenkins controller for Gerrit CI"
  numExecutors: 0
  securityRealm:
    ldap:
      configurations:
        - server: "LDAP_URL"
          rootDN: "LDAP_ROOT_DN"
          managerDN: "LDAP_BIND_DN"
          managerPasswordSecret: "${LDAP_BIND_PASSWORD}"
          userSearchBase: "LDAP_USER_BASE"
          userSearch: "uid={0}"
          groupSearchBase: "LDAP_GROUP_BASE"
  authorizationStrategy:
    globalMatrix:
      entries:
        - user:
            name: "LDAP_ADMIN_USER"
            permissions:
              - "Overall/Administer"
        - group:
            name: "authenticated"
            permissions:
              - "Overall/Read"
              - "Job/Read"
              - "Job/Build"

unclassified:
  location:
    url: "JENKINS_URL"
```

Set `LDAP_ADMIN_USER` to the reviewed LDAP login name for this Jenkins
deployment. This is a site-specific operator input, not a prescribed account
name. The `user` entry grants that exact LDAP identity administrator access;
matrix authorization does not create a Jenkins group or manage LDAP group
membership. The `authenticated` entry grants every authenticated LDAP user
read and build access.

Set the Jenkins location URL to the URL users enter in their browser. In
production behind a reverse proxy or load balancer, this should normally be the
external HTTPS URL, for example `https://jenkins.example.internal/`, even when
Jenkins listens internally on plain HTTP.

If `rootDN` is set, `userSearchBase` and `groupSearchBase` should normally be relative to that root, for example `ou=people` and `ou=groups`. If your organization provides absolute base DNs such as `ou=people,dc=example,dc=internal`, either remove `rootDN` or convert the search bases to relative values. Mixing `rootDN` with absolute search bases can make LDAP searches target the wrong DN.

Protect the JCasC file because it contains the reviewed LDAP bind password:

```bash
sudo chown jenkins:jenkins /var/lib/jenkins/jcasc/jenkins.yaml
sudo chmod 0600 /var/lib/jenkins/jcasc/jenkins.yaml
```

The systemd unit from Section 3.2 already exports this JCasC path.

### 3.5 Start Jenkins

Start Jenkins only after plugins and the selected configuration path are ready:

```bash
sudo systemctl start jenkins
systemctl status --no-pager jenkins
journalctl -u jenkins -n 100 --no-pager
```

Stop if startup fails. Inspect the bounded journal output, correct the owning
configuration or artifact defect, and start again. After later plugin or JCasC
changes, restart Jenkins explicitly with `sudo systemctl restart jenkins`.
Validation observes the enabled and active unit; it does not start or repair
Jenkins.

## 4. UI-Driven Configuration Fallback

Use this section only when the UI-driven path was selected in Section 3.4 and
Jenkins is running from Section 3.5.

1. Browse to `http://JENKINS_HOST:JENKINS_HTTP_PORT/`.
2. Use the initial admin password:

   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

3. Open `Manage Jenkins` > `Plugins` > `Installed plugins` and confirm the
   staged required plugins are enabled without load errors. Do not replace the
   reviewed bundle with unreviewed Update Center installs.
4. Open `Manage Jenkins` > `Security`, select LDAP as the security realm, and
   enter the reviewed LDAP URL, user search base, group search base, manager DN,
   and bind secret according to site policy.
5. Configure authorization with `matrix-auth` from the same `Security` page,
   granting `Overall/Administer` to the exact reviewed `LDAP_ADMIN_USER` LDAP
   user. Grant the built-in `authenticated` SID `Overall/Read`, `Job/Read`, and
   `Job/Build`. Do not create or assume an administrator group.
6. Save only after the LDAP settings and administrator identity are reviewed.
   The setup-wizard administrator is a bootstrap identity; its local password
   does not remain an authentication fallback after LDAP becomes the security
   realm. Sign out and confirm `LDAP_ADMIN_USER` can sign in and open
   `Manage Jenkins` before ending the change window.
7. Open `Manage Jenkins` > `System` and set the Jenkins URL to the reviewed
   browser URL users enter, normally `JENKINS_URL`.
8. Open `Manage Jenkins` > `Nodes` > built-in node or `Configure System`,
   depending on the installed UI, and keep the built-in node executor count at
   zero.
9. Defer the `jenkins-gerrit` Gerrit integration account SSH key and Gerrit
   Trigger configuration until integration-native operations.

## 5. Shared Integration Handoff

### 5.1 Outbound SSH Build Agent Inputs

Do not run builds on the Jenkins controller. Keep the built-in node at zero
executors and provide build capacity through agents. This deployment uses
Jenkins' SSH launcher: the controller connects out to the build server over
SSH. Prepare that host with `docs/operations/native/jenkins-agent.md`.

Complete Section 6 before integration. Controller readiness stops before
keypair and credential creation, public-key handoff, agent node registration,
scheduling, Gerrit Trigger configuration, event streaming, and `Verified`
voting. Perform those cross-role operations with
`docs/operations/native/integration.md` only after the controller and agent
host are both ready.

Credential custody remains fixed:

- The Jenkins controller owns the Jenkins-to-Gerrit private key.
- The Jenkins controller owns the Jenkins-to-agent private key.
- Gerrit and the Jenkins agent consume only matching public keys.
- Do not create a separate controller evidence record. Record the required role
  outcomes only in `docs/operations/native/acceptance-checklist.md`.
- Do not place private keys, passwords, tokens, LDAP bind secrets, or
  secret-bearing configuration in the checklist or referenced native manuals.

## 6. Controller-Only Validation

Run:

```bash
java -version
systemctl is-enabled jenkins
systemctl is-active jenkins
systemctl show jenkins --property=User --property=Group --property=MainPID --no-pager
curl -I http://JENKINS_HOST:JENKINS_HTTP_PORT/
journalctl -u jenkins -n 100 --no-pager
```

`systemctl is-enabled` must report `enabled`, and `systemctl is-active` must
report `active`. The `systemctl show` output must report the reviewed Jenkins
runtime user and group and a nonzero `MainPID`. Stop if any value differs from
the reviewed service configuration.

Acceptance checks:

- OpenJDK 21 is active.
- Jenkins starts under systemd.
- LDAP users can log in.
- Required plugins load successfully.
- An authenticated request to `<JENKINS_URL>/api/json` returns a successful
  JSON response.
- Gerrit SSH, Gerrit event streaming, Jenkins agent scheduling, and `Verified`
  vote checks are deferred to `docs/operations/native/integration.md`.
- Do not accept rendered Gerrit Trigger config, keypairs, node registration,
  scheduling records, or trigger/vote proof as controller-only validation.

Use the Jenkins Web UI to complete the application checks:

1. Browse to `JENKINS_URL` and sign in as the reviewed Jenkins administrator.
2. In the authenticated browser session, open `<JENKINS_URL>/api/json` and
   confirm Jenkins returns a successful JSON object rather than a login or
   error page.
3. Open `Manage Jenkins` and confirm no administrative monitor reports a plugin
   load failure for required plugins.
4. Open `Manage Jenkins` > `Security` and confirm the active LDAP and
   authorization settings match the reviewed JCasC or UI-driven configuration
   without exposing bind secrets in the checklist or its references.
5. Open `Manage Jenkins` > `Nodes` and confirm the built-in node has zero
   executors.

The reboot check is optional. To perform it, use the site's reviewed reboot
procedure, wait for the target to return, and rerun the validation above
without starting, enabling, or repairing Jenkins. Leave the optional checklist
item unchecked when the check is not performed. If the check is attempted and
Jenkins does not return to the same ready state, mark the run `BLOCKED`.

## 7. Backup and Operations

Treat the complete `/var/lib/jenkins` tree as the recovery unit. It includes
Jenkins configuration, jobs, build state, plugins, credentials, JCasC, and the
Jenkins-to-Gerrit and Jenkins-to-agent private keys created during integration.
The backup is secret-bearing even when its contents are not inspected.

Before a backup, record:

- `JENKINS_BACKUP_ROOT`: approved protected local or mounted backup storage.
- `BACKUP_ID`: a unique timestamp or change identifier that does not already
  exist below `JENKINS_BACKUP_ROOT`.

Prefer a site-approved filesystem or storage snapshot that atomically covers
the complete Jenkins home. Retain the snapshot under the unique `BACKUP_ID`
and use the storage platform's native validation to confirm it is complete and
readable.

When a consistent snapshot is unavailable, schedule controller downtime and
copy the stopped Jenkins home. Run each command separately:

```bash
sudo systemctl stop jenkins
systemctl is-active jenkins
sudo test ! -e JENKINS_BACKUP_ROOT/jenkins-BACKUP_ID
sudo install -d -m 0700 -o root -g root \
  JENKINS_BACKUP_ROOT/jenkins-BACKUP_ID
sudo rsync -aHAX --numeric-ids \
  /var/lib/jenkins/ \
  JENKINS_BACKUP_ROOT/jenkins-BACKUP_ID/
sudo rsync -aHAXnc --delete --numeric-ids --itemize-changes \
  /var/lib/jenkins/ \
  JENKINS_BACKUP_ROOT/jenkins-BACKUP_ID/
sudo systemctl start jenkins
```

`systemctl is-active` must report `inactive` before the copy. The `test`
command must succeed so an existing backup is never overwritten. The checksum
comparison must produce no itemized changes. Stop and select storage that
preserves hard links, ACLs, extended attributes, and numeric ownership if
either `rsync` command reports an unsupported feature.

If copying or comparison fails, the backup failed. Start Jenkins, rerun all
Section 6 validation to end the outage safely, and investigate before the next
backup attempt. After a successful copy, start Jenkins and rerun the same
validation before closing the backup window.

Protect every backup with production-equivalent access restrictions and
encryption in transit and at rest. Retain multiple backup versions. Replicate
the completed local or mounted backup to remote storage only through the
site-approved protected transfer path; do not stream a live Jenkins home
directly to a remote destination.

Periodically prove that a backup can be restored in an isolated environment.
Use the matching Jenkins core and reviewed plugin versions, keep the isolated
controller stopped while restoring the complete home, and preserve the
reviewed numeric runtime UID and GID. Start the isolated controller only after
ownership is verified, then run all Section 6 validation. Never test a restore
by overwriting an active production Jenkins home.

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
- Jenkins stable Debian package metadata: https://pkg.jenkins.io/debian-stable/binary/Packages
- Jenkins stable update center: https://updates.jenkins.io/stable/update-center.actual.json
