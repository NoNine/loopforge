# Gerrit Native Operations Reference

This document is the manual target-deployment native operations reference for
Gerrit. It uses OS and application-native operations only, not repository
automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Public internet fallback on target hosts is simulation-only and must be labeled
as such in docs, logs, and verification summaries.

Gerrit application artifact bundles are key-free. They may contain reviewed
Gerrit application files, templates, manifests, and checksums, but not external
Gerrit plugin jars, SSH private keys, public keys, `authorized_keys`, or
generated public-key handoff files. Jenkins-to-Gerrit keypair generation and
public-key handoff are integration operations after Gerrit role-local readiness
is proven.


Audience: production operators installing Gerrit on Ubuntu 24.04 LTS without Docker.

Use this manual with `integration-native-operations-reference.md` after Gerrit
role-local readiness is proven and the deployment is ready for shared
Gerrit/Jenkins integration.

Assumptions:

- Gerrit runs on its own Ubuntu 24.04 LTS host.
- Jenkins runs on a separate host and will integrate with Gerrit later.
- Identity is integrated with LDAP/Active Directory.
- Gerrit exposes direct service ports on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Gerrit application artifacts.
- Production host commands are run by the operator account with `sudo` or
  equivalent delegated administrator privileges unless noted. Do not use
  `root` as a Loopforge account or direct login identity.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, and Gerrit
`3.13.6`. `docs/version-baseline.md` owns the package-wide baseline and
reviewed update rules.

Production warning: direct HTTP service ports are documented because that is the selected deployment model. For production environments outside a trusted network, terminate TLS with a reverse proxy or enterprise load balancer before exposing Gerrit to users.

Privilege warning: a production Gerrit install cannot be completed by an
unprivileged user alone. Package installation, `/etc`, `/srv/gerrit`, file
ownership, systemd units, service restarts, and protected secret files require
delegated administrator privilege from the operator account. Root may own
OS-reserved files, but root is not a Loopforge account, helper execution
identity, runtime identity, or supported direct login identity.

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
| Browser URL | `GERRIT_CANONICAL_WEB_URL`, such as `https://gerrit.example.internal/` |
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
Gerrit application artifacts on a permitted staging machine, draft
`gerrit.config` and `secure.config` values, collect required host/DNS/LDAP
values, and run network checks that your account is allowed to run.

Ask an administrator to perform or delegate these production-host tasks:

- Install OS packages and Java dependencies.
- Confirm the local Gerrit runtime account and group exist on the Gerrit host.
- Create and own `/srv/gerrit`, `/srv/gerrit/bin`, `/srv/gerrit/plugins`, and any
  staged `/var/lib/loopforge/staging/gerrit` content as documented.
- Place `/srv/gerrit/bin/gerrit.war`, initialize Gerrit as `gerrit`, and protect `/srv/gerrit/etc/secure.config`.
- Create `/etc/systemd/system/gerrit.service`, reload systemd, and start, stop, restart, or enable Gerrit.
- Run any `chown`, `chmod`, `apt`, `dpkg`, `systemctl`, or writes under `/etc`, `/opt`, or `/srv`.

A home-directory Gerrit process can be useful for lab validation, but it is not this production deployment. It will not match the documented systemd service management, ownership model, backup paths, or secret handling.

## 2. Dependencies And Gerrit Artifact Bundle

### 2.1 Ubuntu Dependencies

The package rationale and layered classification are maintained in
`docs/package-requirements.md`.

Run on the Gerrit host:

```bash
apt update
apt install -y \
  ca-certificates \
  curl \
  openssh-client \
  openjdk-21-jre-headless \
  rsync \
  tar
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
mkdir -p ~/gerrit-artifacts-bundle/gerrit
cd ~/gerrit-artifacts-bundle/gerrit
wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
  --continue -O gerrit-3.13.6.war \
  https://gerrit-releases.storage.googleapis.com/gerrit-3.13.6.war
```

Do not add external Gerrit plugin jars to the Loopforge Gerrit artifact bundle.
External plugins are operator-managed manual operations after Loopforge has
installed and validated core Gerrit.

Verify the Gerrit WAR archive:

```bash
cd ~/gerrit-artifacts-bundle/gerrit
unzip -t gerrit-3.13.6.war >/dev/null
```

Create manifests, checksums, and archive:

```bash
cd ~/gerrit-artifacts-bundle
cat > gerrit/manifest.txt <<'EOF'
harness_manifest_version=1
role=gerrit
bundle_name=gerrit-artifacts-bundle
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
gerrit_version=3.13.6
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
war=gerrit-3.13.6.war
template_count=2
EOF
(cd gerrit && find . -type f ! -name checksums.sha256 -print0 \
  | sort -z | xargs -0 sha256sum > checksums.sha256)
tar -czf ~/gerrit-artifacts-bundle.tar.gz -C ~/gerrit-artifacts-bundle gerrit
sha256sum ~/gerrit-artifacts-bundle.tar.gz > ~/gerrit-artifacts-bundle.tar.gz.sha256
```

The approved Gerrit release unit is the artifact archive and its `.sha256`
file.

#### 2.2.2 Install the Gerrit Artifact Bundle Manually

Transfer the artifact archive and `.sha256` file to the Gerrit host with
approved media or an approved internal transfer path. Run on the Gerrit host:

```bash
operator_account="${LOOPFORGE_OPERATOR_ACCOUNT:-ci-operator}"
operator_group="${LOOPFORGE_OPERATOR_GROUP:-$operator_account}"
operator_home="$(getent passwd "$operator_account" | cut -d: -f6)"
[ -n "$operator_home" ] || {
  printf 'missing operator account: %s\n' "$operator_account" >&2
  exit 1
}

cd "$operator_home"
sha256sum -c gerrit-artifacts-bundle.tar.gz.sha256
sudo install -d -m 0750 -o "$operator_account" -g "$operator_group" /var/lib/loopforge/staging
sudo rm -rf /var/lib/loopforge/staging/gerrit
sudo tar -xzf gerrit-artifacts-bundle.tar.gz -C /var/lib/loopforge/staging
sudo chown -R "$operator_account:$operator_group" /var/lib/loopforge/staging/gerrit
cd /var/lib/loopforge/staging/gerrit
sha256sum -c checksums.sha256
java -version
```

Install the Gerrit artifact files:

```bash
sudo install -d -m 0750 /srv/gerrit
sudo groupadd --gid 61010 gerrit || true
sudo useradd --uid 61010 --gid 61010 --home-dir /srv/gerrit --shell /bin/bash gerrit || true
sudo chown gerrit:gerrit /srv/gerrit
sudo install -d -o gerrit -g gerrit -m 0755 /srv/gerrit/bin
sudo cp /var/lib/loopforge/staging/gerrit/gerrit-3.13.6.war /srv/gerrit/bin/gerrit.war
sudo chown gerrit:gerrit /srv/gerrit/bin/gerrit.war
sudo install -d -o gerrit -g gerrit -m 0755 /srv/gerrit/plugins
sudo install -d -o gerrit -g gerrit -m 0750 /srv/gerrit/etc
```

For artifact recovery, rerun only the artifact archive checksum, extraction,
and WAR copy commands. OS package recovery uses the approved internal
Ubuntu/OS package repository path.

## 3. Gerrit Installation

### 3.1 Confirm Service Account and Create Directories

Run on the Gerrit host:

```bash
getent passwd gerrit
getent group gerrit
install -d -o gerrit -g gerrit -m 0750 /srv/gerrit
install -d -o gerrit -g gerrit -m 0755 /srv/gerrit/bin
```

Place the Gerrit WAR from the staged bundle-factory artifact bundle. Target
hosts must not download Gerrit application artifacts as fallback.

```bash
cp /var/lib/loopforge/staging/gerrit/gerrit-3.13.6.war /srv/gerrit/bin/gerrit.war
chown gerrit:gerrit /srv/gerrit/bin/gerrit.war
```

### 3.2 Initialize Gerrit

Run initialization as the `gerrit` user:

```bash
sudo -u gerrit java -jar /srv/gerrit/bin/gerrit.war init -d /srv/gerrit
```

Recommended answers:

- Git repositories: `/srv/gerrit/git`
- Index type: `lucene`
- Authentication method: `LDAP`
- HTTP daemon listen URL: `http://*:8080/`
- SSH daemon listen port: `29418`
- Built-in plugin prompts: install only site-approved built-in plugins; keep
  plugin scope minimal.

For offline installation, do not allow `init` to fetch optional libraries from the internet unless the artifact was staged.

### 3.3 Configure Gerrit

Edit `/srv/gerrit/etc/gerrit.config`:

```ini
[gerrit]
  basePath = git
  canonicalWebUrl = GERRIT_CANONICAL_WEB_URL
  serverId = REPLACE_WITH_GENERATED_OR_STABLE_UUID

[index]
  type = lucene

[auth]
  type = LDAP
  gitBasicAuthPolicy = HTTP_LDAP

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

Set `GERRIT_CANONICAL_WEB_URL` to the URL users enter in their browser. In production
behind a reverse proxy or load balancer, this should normally be the external
HTTPS URL, for example `https://gerrit.example.internal/`, even when Gerrit
listens internally on plain HTTP.

Use `gitBasicAuthPolicy = HTTP_LDAP` when REST API or Git-over-HTTP clients
must support both Gerrit-generated HTTP auth tokens and LDAP passwords. Human
LDAP-backed users can still authenticate with LDAP passwords, while Gerrit
service accounts such as `jenkins-gerrit` use Gerrit-generated HTTP auth
tokens.

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

External Gerrit plugins are operator-managed. Loopforge does not fetch, bundle,
install, checksum, or validate plugin jars because external plugin delivery is
not stable enough for the v1 bundle contract.

Common operator-selected plugins include:

- `events-log`: enables missed-event replay for Jenkins Gerrit Trigger.
- `metrics-reporter-prometheus`: exports operational metrics.
- `healthcheck`: optional health checks for monitoring.

Repository replication, outbound webhooks, ownership, HA, event-broker, and
issue-tracker plugins are deployment-specific operator choices.

Plugin rule: Gerrit plugin jars must match the selected Gerrit major/minor line.
Operators should source plugins from approved internal mirrors or reviewed
artifact sources, record checksums outside the Loopforge bundle, install jars
under `/srv/gerrit/plugins`, and restart Gerrit under the documented service
control path.

Manual operator example:

```bash
install -d -o gerrit -g gerrit /srv/gerrit/plugins
install -m 0644 -o gerrit -g gerrit /approved/plugin.jar /srv/gerrit/plugins/plugin.jar
sha256sum /srv/gerrit/plugins/plugin.jar
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

## 4. Shared Integration Handoff

Gerrit-native role readiness stops before cross-role Jenkins integration.
The Gerrit role proves the Gerrit service, LDAP configuration, HTTP endpoint,
SSH endpoint, runtime account, staged artifacts, and bounded evidence. It does
not register Jenkins public keys, create Gerrit Trigger credentials, install or
validate external Gerrit plugins, grant stream-events permission, apply
`Verified` voting grants, or prove trigger delivery.

Later cross-role work belongs to the separate integration workflow, not this
role-local native reference. That later workflow owns Jenkins-to-Gerrit
public-key registration, Gerrit integration permissions, `Verified`
label/grant application, stream-events validation, trigger validation, and
integration evidence. Until that workflow is implemented, this native
reference remains limited to Gerrit role-local readiness.

Credential custody remains fixed:

- The Jenkins controller owns the Jenkins-to-Gerrit private key.
- Gerrit consumes only the matching public key.
- Gerrit evidence may record public-key fingerprints, accounts, endpoints,
  bounded log paths, and redaction status.
- Gerrit evidence must not contain private keys, passwords, tokens, LDAP bind
  secrets, or full secret-bearing env values.

## 5. Validation

Run:

```bash
java -version
systemctl is-enabled gerrit
systemctl is-active gerrit
curl -I http://GERRIT_HOST:8080/
ssh -p 29418 USER@GERRIT_HOST gerrit version
tail -n 100 /srv/gerrit/logs/gerrit.log
```

Acceptance checks:

- OpenJDK 21 is active.
- Gerrit starts under systemd.
- Gerrit survives reboot.
- LDAP users can log in.
- Gerrit SSH works on port `29418`.
- Jenkins integration prerequisites from Section 4 are deferred to
  `integration-native-operations-reference.md`.

Use the Gerrit Web UI to complete the application checks:

1. Browse to `GERRIT_CANONICAL_WEB_URL`.
2. Sign in with the reviewed Gerrit administrator account.
3. Open the user menu > `Settings` and confirm the administrator account is a
   real Gerrit account, not only an LDAP directory entry.
4. Open `Browse` > `Repositories` and confirm `All-Projects` is visible.
5. Open `Browse` > `Groups` or the installed UI's equivalent group page and
   confirm the reviewed administrator group is visible.
6. Sign out and sign in as the reviewed test user if one is required for later
   integration proof.

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
- Rebuild the Gerrit artifact bundle and record checksums for every approved
  application artifact upgrade.
- If operators install external plugins, use jars built for the same Gerrit
  major/minor line and track their source approvals outside the Loopforge
  bundle.

## 7. References

- Jenkins controller native operations:
  `jenkins-controller-native-operations-reference.md`
- Integration native operations:
  `integration-native-operations-reference.md`
- Gerrit downloads: https://www.gerritcodereview.com/
- Gerrit support status: https://www.gerritcodereview.com/support.html
- Gerrit install documentation: https://gerrit-review.googlesource.com/Documentation/install.html
- Gerrit init command: https://gerrit-review.googlesource.com/Documentation/pgm-init.html
- Gerrit reverse proxy documentation: https://gerrit-review.googlesource.com/Documentation/config-reverseproxy.html
- Gerrit plugin documentation: https://gerrit-review.googlesource.com/Documentation/config-plugins.html
- Gerrit 3.14 release notes: https://gerrit.googlesource.com/homepage/+/refs/heads/master/pages/site/releases/3.14.md
- Gerrit 3.13 release notes: https://gerrit.googlesource.com/homepage/+/refs/heads/master/pages/site/releases/3.13.md
