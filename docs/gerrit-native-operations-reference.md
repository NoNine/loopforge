# Gerrit Native Operations Reference

This document is a native operations reference. It uses OS and
application-native operations only, not repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Public internet fallback on target hosts is simulation-only and must be labeled
as such in docs, logs, and verification summaries.


Audience: production operators installing Gerrit on Ubuntu 24.04 LTS without Docker.

Use this manual with `jenkins-controller-native-operations-reference.md` when
validating the full Gerrit/Jenkins integration.

Assumptions:

- Gerrit runs on its own Ubuntu 24.04 LTS host.
- Jenkins runs on a separate host and will integrate with Gerrit later.
- Identity is integrated with LDAP/Active Directory.
- Gerrit exposes direct service ports on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Gerrit application artifacts.
- Production host commands are run with `sudo` or equivalent delegated administrator privileges unless noted.

Recommended versions as of 2026-06-09:

- Gerrit: `3.13.6` for conservative production rollout.
- Gerrit `3.14.0` is the current/latest line, but a `.0` release should be tested carefully before production.
- Java: OpenJDK 21.

Production warning: direct HTTP service ports are documented because that is the selected deployment model. For production environments outside a trusted network, terminate TLS with a reverse proxy or enterprise load balancer before exposing Gerrit to users.

Privilege warning: a production Gerrit install cannot be completed by an unprivileged user alone. Package installation, `/etc`, `/opt`, `/srv/gerrit`, file ownership, systemd units, service restarts, and protected secret files require root or delegated sudo.

Manual authority: this manual is the reference procedure. It intentionally
contains only native OS and Gerrit operations. Do not add repository automation
commands or automation-equivalent command tables to this document.


## 1. Operator Inputs and Current Status

Record these values before installation:

| Item | Value |
| --- | --- |
| Hostname | `GERRIT_HOST` |
| IP address | `GERRIT_IP` |
| DNS name | `gerrit.example.internal` |
| HTTP port | `8080` or chosen port |
| SSH port | `29418` |
| LDAP URL | `ldap://LDAP_HOST:389` or `ldaps://LDAP_HOST:636` |
| LDAP bind DN | `uid=gerrit-ldap-bind,LDAP_USER_BASE` or provided bind DN |
| LDAP user base | `LDAP_USER_BASE` |
| LDAP group base | `LDAP_GROUP_BASE` |
| Network mode | Approved internal OS repositories for target-host OS dependencies |
| Gerrit runtime user | `gerrit`, local OS account |
| Gerrit runtime group | `gerrit`, local OS group |
| Jenkins Gerrit integration account | `jenkins-gerrit`, Gerrit-internal account |
| Data directory | `/srv/gerrit`, owned by `gerrit:gerrit` |

Run on the Gerrit host:

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
dpkg -l | egrep 'openjdk|git|curl|wget|openssh|rsync|unzip' || true
systemctl --failed
ss -lntup
getent hosts GERRIT_HOST
getent passwd gerrit
getent group gerrit
nc -vz LDAP_HOST 389 || true
nc -vz LDAP_HOST 636 || true
```

Use port `389` for LDAP with StartTLS if required. Use port `636` for LDAPS.

The Gerrit runtime user and group are local OS identities. Create or confirm
`gerrit:gerrit` before installation, or use your site's chosen local runtime
account consistently everywhere this manual shows `gerrit`.

The LDAP bind DN used by Gerrit should be a dedicated read-only Gerrit bind
account. It must have permission to search the configured user and group bases.
A bind account that can authenticate but cannot search those subtrees will
still prevent LDAP account provisioning, HTTP authentication, and group
resolution.

### 1.1 If You Do Not Have Root Privileges

Use this manual as an administrator handoff. Without root, you can prepare
Gerrit application artifacts on a permitted staging machine, stage Gerrit
plugin jars for review, draft `gerrit.config` and `secure.config` values,
collect required host/DNS/LDAP values, and run network checks that your
account is allowed to run.

Ask an administrator to perform or delegate these production-host tasks:

- Install OS packages and Java dependencies.
- Confirm the local Gerrit runtime account and group exist on the Gerrit host.
- Create and own `/srv/gerrit`, `/srv/gerrit/plugins`, `/opt/gerrit`, and any
  staged `/opt/gerrit-artifacts-bundle` content as documented.
- Place `/opt/gerrit/gerrit.war`, initialize Gerrit as `gerrit`, and protect `/srv/gerrit/etc/secure.config`.
- Create `/etc/systemd/system/gerrit.service`, reload systemd, and start, stop, restart, or enable Gerrit.
- Run any `chown`, `chmod`, `apt`, `dpkg`, `systemctl`, or writes under `/etc`, `/opt`, or `/srv`.

A home-directory Gerrit process can be useful for lab validation, but it is not this production deployment. It will not match the documented systemd service management, ownership model, backup paths, or secret handling.

## 2. Dependencies And Gerrit Artifact Bundle

### 2.1 OS Dependency Installation

Run on the Gerrit host:

```bash
apt update
apt install -y \
  ca-certificates \
  curl \
  git \
  openssh-client \
  openjdk-21-jre-headless \
  rsync \
  tar \
  unzip \
  wget
java -version
```

Expected result: OpenJDK 21.

### 2.2 Gerrit Artifact Bundle

v1 does not support installing OS dependencies from locally bundled Ubuntu
packages. Use approved internal Ubuntu/OS package repositories for OS packages
on target hosts.

Prepare Gerrit application artifacts in staging or a bundle-factory
environment, then stage only the reviewed application artifact archive to the
Gerrit host.

Official source reference:

```text
https://gerrit-releases.storage.googleapis.com/gerrit-3.13.6.war
```

#### 2.2.1 Create the Gerrit Artifact Bundle

Run on the bundle-factory VM:

```bash
mkdir -p ~/gerrit-artifacts-bundle/{gerrit/plugins,checksums}
cd ~/gerrit-artifacts-bundle/gerrit
wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
  --continue -O gerrit-3.13.6.war \
  https://gerrit-releases.storage.googleapis.com/gerrit-3.13.6.war
cat > plugins.seed.txt <<'EOF'
events-log
metrics-reporter-prometheus
healthcheck
EOF
```

Download the selected Gerrit plugin jars on the bundle-factory VM:

```bash
cd ~/gerrit-artifacts-bundle/gerrit
wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
  --continue -O plugins/events-log.jar \
  https://gerrit-ci.gerritforge.com/job/plugin-events-log-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/events-log/events-log.jar
wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
  --continue -O plugins/metrics-reporter-prometheus.jar \
  https://gerrit-ci.gerritforge.com/job/plugin-metrics-reporter-prometheus-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/metrics-reporter-prometheus/metrics-reporter-prometheus.jar
wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
  --continue -O plugins/healthcheck.jar \
  https://gerrit-ci.gerritforge.com/job/plugin-healthcheck-bazel-stable-3.13/lastSuccessfulBuild/artifact/bazel-bin/plugins/healthcheck/healthcheck.jar
```

Plugin compatibility rules:

- Every staged plugin jar must be built for the selected Gerrit major/minor
  line, for example Gerrit `3.13.x`.
- Do not use plugin jars built for another Gerrit line unless the plugin
  maintainer explicitly documents compatibility.
- Treat missing expected plugins or unexpected extra plugin jars as
  release-blocking issues.
- Add `replication` or `webhooks` later only after selecting approved compatible
  plugin artifact URLs for the selected Gerrit line.

Create manifests, checksums, and archive:

```bash
cd ~/gerrit-artifacts-bundle
find gerrit/plugins -type f -name '*.jar' -printf '%f\n' \
  | sort > gerrit/plugin-artifacts.manifest
sed 's/$/.jar/' gerrit/plugins.seed.txt | sort > gerrit/plugin-seed-jars.expected
comm -23 gerrit/plugin-seed-jars.expected gerrit/plugin-artifacts.manifest \
  > gerrit/plugin-artifacts.missing
test ! -s gerrit/plugin-artifacts.missing
printf 'bundle_kind=gerrit-artifacts\ngerrit_version=3.13.6\ngerrit_war=gerrit-3.13.6.war\nplugin_seed=plugins.seed.txt\nplugin_artifacts=plugin-artifacts.manifest\n' \
  > gerrit/release-unit.manifest
find . -type f ! -path './checksums/SHA256SUMS' -print0 \
  | sort -z | xargs -0 sha256sum > checksums/SHA256SUMS
tar -czf ~/gerrit-artifacts-bundle.tar.gz -C ~ gerrit-artifacts-bundle
sha256sum ~/gerrit-artifacts-bundle.tar.gz > ~/gerrit-artifacts-bundle.tar.gz.sha256
```

The approved Gerrit release unit is the combination of the artifact archive,
its `.sha256` file, the internal `SHA256SUMS` file, `plugins.seed.txt`,
`plugin-artifacts.manifest`, and `release-unit.manifest`.

#### 2.2.2 Install the Gerrit Artifact Bundle Manually

Transfer the artifact archive and `.sha256` file to the Gerrit host with
approved media or an approved internal transfer path. Run on the Gerrit host:

```bash
cd /home/operator
sha256sum -c gerrit-artifacts-bundle.tar.gz.sha256
sudo rm -rf /opt/gerrit-artifacts-bundle
sudo tar -xzf gerrit-artifacts-bundle.tar.gz -C /opt
cd /opt/gerrit-artifacts-bundle
sha256sum -c checksums/SHA256SUMS
java -version
```

Install the Gerrit artifact files:

```bash
sudo install -d -m 0750 /srv/gerrit
sudo groupadd --system gerrit || true
sudo useradd --system --gid gerrit --home-dir /srv/gerrit --shell /bin/bash gerrit || true
sudo chown gerrit:gerrit /srv/gerrit
sudo install -d -o gerrit -g gerrit -m 0755 /opt/gerrit
sudo cp /opt/gerrit-artifacts-bundle/gerrit/gerrit-3.13.6.war /opt/gerrit/gerrit.war
sudo chown gerrit:gerrit /opt/gerrit/gerrit.war
sudo install -d -o gerrit -g gerrit -m 0755 /srv/gerrit/plugins
sudo cp /opt/gerrit-artifacts-bundle/gerrit/plugins/*.jar /srv/gerrit/plugins/ 2>/dev/null || true
sudo chown gerrit:gerrit /srv/gerrit/plugins/*.jar 2>/dev/null || true
```

For artifact recovery, rerun only the artifact archive checksum, extraction,
WAR copy, and plugin copy commands. OS package recovery uses the approved
internal Ubuntu/OS package repository path.

## 3. Gerrit Installation

### 3.1 Confirm Service Account and Create Directories

Run on the Gerrit host:

```bash
getent passwd gerrit
getent group gerrit
install -d -o gerrit -g gerrit -m 0750 /srv/gerrit
install -d -o gerrit -g gerrit -m 0755 /opt/gerrit
```

Place the Gerrit WAR.

Online:

```bash
wget -O /opt/gerrit/gerrit.war \
  https://gerrit-releases.storage.googleapis.com/gerrit-3.13.6.war
chown gerrit:gerrit /opt/gerrit/gerrit.war
```

Offline:

```bash
cp /opt/gerrit-artifacts-bundle/gerrit/gerrit-3.13.6.war /opt/gerrit/gerrit.war
chown gerrit:gerrit /opt/gerrit/gerrit.war
```

### 3.2 Initialize Gerrit

Run initialization as the `gerrit` user:

```bash
sudo -u gerrit java -jar /opt/gerrit/gerrit.war init -d /srv/gerrit
```

Recommended answers:

- Git repositories: `/srv/gerrit/git`
- Index type: `lucene`
- Authentication method: `LDAP`
- HTTP daemon listen URL: `http://*:8080/`
- SSH daemon listen port: `29418`
- Core plugins: install only required plugins; keep plugin scope minimal.

For offline installation, do not allow `init` to fetch optional libraries from the internet unless the artifact was staged.

### 3.3 Configure Gerrit

Edit `/srv/gerrit/etc/gerrit.config`:

```ini
[gerrit]
  basePath = git
  canonicalWebUrl = http://GERRIT_HOST:8080/
  serverId = REPLACE_WITH_GENERATED_OR_STABLE_UUID

[index]
  type = lucene

[auth]
  type = LDAP
  gitBasicAuthPolicy = LDAP

[ldap]
  server = ldap://LDAP_HOST:389
  username = LDAP_BIND_DN
  accountBase = LDAP_USER_BASE
  groupBase = LDAP_GROUP_BASE
  referral = follow

[httpd]
  listenUrl = http://*:8080/

[sshd]
  listenAddress = *:29418

[container]
  javaHome = /usr/lib/jvm/java-21-openjdk-amd64
  user = gerrit

[cache]
  directory = cache
```

Set `canonicalWebUrl` to the URL users enter in their browser. In production
behind a reverse proxy or load balancer, this should normally be the external
HTTPS URL, for example `https://gerrit.example.internal/`, even when Gerrit
listens internally on plain HTTP.

Use `gitBasicAuthPolicy = LDAP` when REST API or Git-over-HTTP clients should authenticate with the user's LDAP password. `gitBasicAuthPolicy = HTTP` expects a Gerrit-generated HTTP password for an already provisioned account, which is a different operational model.

Store LDAP bind password in `/srv/gerrit/etc/secure.config`:

```ini
[ldap]
  password = REPLACE_WITH_LDAP_BIND_PASSWORD
```

Set permissions:

```bash
chown -R gerrit:gerrit /srv/gerrit
chmod 0600 /srv/gerrit/etc/secure.config
```

### 3.4 Install Gerrit Plugins

Recommended production plugins:

- `events-log`: enables missed-event replay for Jenkins Gerrit Trigger.
- `metrics-reporter-prometheus`: exports operational metrics.
- `healthcheck`: optional health checks for monitoring.

Repository replication and outbound webhooks can be added later after approved
compatible plugin artifact URLs are selected.

Plugin rule: Gerrit plugin jars must match the selected Gerrit major/minor line.

Install the plugins staged in the Gerrit artifact bundle:

```bash
install -d -o gerrit -g gerrit /srv/gerrit/plugins
cp /opt/gerrit-artifacts-bundle/gerrit/plugins/*.jar /srv/gerrit/plugins/
chown gerrit:gerrit /srv/gerrit/plugins/*.jar
```

### 3.5 Create Gerrit systemd Service

Create `/etc/systemd/system/gerrit.service`:

```ini
[Unit]
Description=Gerrit Code Review
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=gerrit
Group=gerrit
Environment=GERRIT_SITE=/srv/gerrit
ExecStart=/srv/gerrit/bin/gerrit.sh start
ExecStop=/srv/gerrit/bin/gerrit.sh stop
ExecReload=/srv/gerrit/bin/gerrit.sh restart
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
systemctl daemon-reload
systemctl enable --now gerrit
systemctl status gerrit
journalctl -u gerrit -n 100 --no-pager
tail -n 100 /srv/gerrit/logs/gerrit.log
```

## 4. Jenkins Integration Prerequisites

Create or confirm the Gerrit-internal `jenkins-gerrit` Jenkins Gerrit
integration account. This account is not an LDAP user and is not a Unix runtime
account; it exists in Gerrit so Jenkins can authenticate over Gerrit SSH.
It does not require a registered email address for normal Jenkins Gerrit Trigger
operation.

This account is distinct from the Jenkins runtime account and any Jenkins administrator account.

After Jenkins generates its SSH key, add the Jenkins public key to the
`jenkins-gerrit` Jenkins Gerrit integration account in Gerrit.

Grant the `jenkins-gerrit` Jenkins Gerrit integration account:

- Membership in a service-user group.
- Permission to stream events if Jenkins uses Gerrit Trigger.
- Permission to read target projects.
- Permission to vote on the `Verified` label.

Do not grant `Forge Author` or `Forge Committer` to the Jenkins integration
account for normal CI trigger and vote workflows. Upload test changes with a
human or dedicated LDAP-backed test uploader account instead; the Jenkins
integration account should receive the event and post the Jenkins vote.

Create or confirm the `Verified` label in Gerrit project config. Gerrit 3.13
rejects new blocking label functions through REST, so use `NoBlock` semantics
for now.

```ini
[label "Verified"]
  function = NoBlock
  defaultValue = 0
  value = -1 Fails
  value =  0 No score
  value = +1 Verified
```

Grant the Jenkins integration account `label-Verified = -1..+1` on the refs where CI jobs are expected to vote. Without this label and permission, Jenkins Gerrit Trigger can still receive events and run builds, but Gerrit will reject the result command when Jenkins tries to report `--verified`.

If Jenkins will use missed-event playback, install and configure Gerrit `events-log`.

## 5. Validation

Run:

```bash
java -version
systemctl is-enabled gerrit
systemctl is-active gerrit
curl -I http://GERRIT_HOST:8080/
ssh -p 29418 USER@GERRIT_HOST gerrit version
ssh -p 29418 jenkins-gerrit@GERRIT_HOST gerrit stream-events
tail -n 100 /srv/gerrit/logs/gerrit.log
```

The `stream-events` command is expected to stay open while waiting for events. Stop it with `Ctrl-C` after confirming it connects without an authorization error.

Acceptance checks:

- OpenJDK 21 is active.
- Gerrit starts under systemd.
- Gerrit survives reboot.
- LDAP users can log in.
- Gerrit SSH works on port `29418`.
- Required plugins load successfully.
- `jenkins-gerrit` can read projects, stream events, and vote on `Verified`.
- A Jenkins-triggered test change receives a Jenkins-authored `Verified +1` or `Verified -1` message in Gerrit.

## 6. Backup and Operations

Back up:

- `/srv/gerrit/etc`
- `/srv/gerrit/git`
- `/srv/gerrit/db`
- `/srv/gerrit/index` if fast restore is required
- `/srv/gerrit/plugins`
- `/srv/gerrit/logs` according to retention policy

Example:

```bash
rsync -aH --numeric-ids /srv/gerrit/ BACKUP_HOST:/backups/gerrit/
```

Protect `/srv/gerrit/etc/secure.config`; losing it can break LDAP or service authentication.

Upgrade principles:

- Back up before every upgrade.
- Test the target Gerrit WAR in staging.
- Use plugins built for the same Gerrit major/minor line.
- Rebuild the Gerrit artifact bundle and record checksums for every approved
  application artifact upgrade.

## 7. References

- Jenkins controller native operations:
  `jenkins-controller-native-operations-reference.md`
- Gerrit downloads: https://www.gerritcodereview.com/
- Gerrit support status: https://www.gerritcodereview.com/support.html
- Gerrit install documentation: https://gerrit-review.googlesource.com/Documentation/install.html
- Gerrit init command: https://gerrit-review.googlesource.com/Documentation/pgm-init.html
- Gerrit reverse proxy documentation: https://gerrit-review.googlesource.com/Documentation/config-reverseproxy.html
- Gerrit plugin documentation: https://gerrit-review.googlesource.com/Documentation/config-plugins.html
- Gerrit 3.14 release notes: https://gerrit.googlesource.com/homepage/+/refs/heads/master/pages/site/releases/3.14.md
- Gerrit 3.13 release notes: https://gerrit.googlesource.com/homepage/+/refs/heads/master/pages/site/releases/3.13.md
