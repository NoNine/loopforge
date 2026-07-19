# Gerrit Native Operations Reference

This document is the manual target-deployment native operations reference for
Gerrit. It uses OS and application-native operations only, not repository
automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Public internet fallback on target hosts is simulation-only and must be labeled
as such in docs, logs, and verification summaries.

Gerrit application artifact bundles are key-free. The native Gerrit payload
contains the reviewed Gerrit WAR and its checksum file, but not external Gerrit
plugin jars, SSH private keys, public keys, `authorized_keys`, or generated
public-key handoff files. Jenkins-to-Gerrit keypair generation and public-key
handoff are integration operations after Gerrit role-local readiness is proven.


Audience: production operators installing Gerrit on Ubuntu 24.04 LTS without Docker.

Use this manual with `docs/operations/native/integration.md` after Gerrit
role-local readiness is proven and the deployment is ready for shared
Gerrit/Jenkins integration.

Assumptions:

- Gerrit runs on its own Ubuntu 24.04 LTS host.
- The target is freshly provisioned with no prior Gerrit or Loopforge runtime
  state, including no Gerrit runtime account, group, or `/srv/gerrit` path.
- Jenkins runs on a separate host and will integrate with Gerrit later.
- Identity is integrated with LDAP/Active Directory.
- Gerrit exposes direct service ports on a trusted/internal network.
- Staging can use an internet-connected Ubuntu 24.04 machine to prepare
  reviewed Gerrit application artifacts.
- Production host commands are run by the operator account with `sudo` or
  equivalent delegated administrator privileges unless noted. Do not use
  `root` as a Loopforge account or direct login identity.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, and Gerrit
`3.13.6`. `docs/baselines/version-baseline.md` owns the package-wide baseline and
reviewed update rules.

Production warning: direct HTTP service ports are documented because that is the selected deployment model. For production environments outside a trusted network, terminate TLS with a reverse proxy or enterprise load balancer before exposing Gerrit to users.

Privilege warning: a production Gerrit install cannot be completed by an
unprivileged user alone. Package installation, `/etc`, `/srv/gerrit`, file
ownership, systemd units, service restarts, and protected secret files require
delegated administrator privilege from the operator account. Root may own
OS-reserved files, but root is not a Loopforge account, runtime identity, or
supported direct login identity.

Manual authority: this manual is the reference procedure. It intentionally
contains only native OS and Gerrit operations. Do not add repository automation
commands or automation-equivalent command tables to this document.


## 1. Operator Inputs and Preflight

Record these values before installation:

| Item | Value |
| --- | --- |
| Hostname | `GERRIT_HOST`, a site-approved stable FQDN or DNS name |
| Browser URL | `GERRIT_CANONICAL_WEB_URL`, such as `https://gerrit.example.internal/` |
| HTTP port | `GERRIT_HTTP_PORT`, default `8080` |
| SSH port | `GERRIT_SSH_PORT`, default `29418` |
| LDAP URL | `LDAP_URL`, such as `ldap://LDAP_HOST:389` or `ldaps://LDAP_HOST:636` |
| LDAP bind DN | `uid=gerrit-ldap-bind,LDAP_USER_BASE` or provided bind DN |
| LDAP user base | `LDAP_USER_BASE` |
| LDAP group base | `LDAP_GROUP_BASE` |
| Gerrit administrator | `GERRIT_ADMIN_ACCOUNT`, reviewed LDAP-backed account |
| Gerrit administrator group | `GERRIT_ADMIN_GROUP`, reviewed LDAP group |
| Gerrit test user | Reviewed LDAP-backed test account |
| Network mode | Approved internal OS repositories for target-host OS dependencies |
| Operator account | `LOOPFORGE_OPERATOR_ACCOUNT`, default `ci-operator` |
| Operator group | `LOOPFORGE_OPERATOR_GROUP`, default `ci-operator` |
| Gerrit runtime user | `gerrit`, local OS account |
| Gerrit runtime group | `gerrit`, local OS group |
| Gerrit runtime UID | `61010`, or reviewed site value |
| Gerrit runtime GID | `61010`, or reviewed site value |
| Data directory | `/srv/gerrit`, owned by `gerrit:gerrit` |

Run on the Gerrit host:

```bash
cat /etc/os-release
hostnamectl
timedatectl
df -h /srv
free -h
systemctl --failed
getent hosts GERRIT_HOST
```

Confirm `/etc/os-release` reports Ubuntu `24.04` and `noble`, the hostname and
time settings match reviewed inventory, `/srv` has sufficient capacity, and
any failed systemd units have an approved disposition. The final command must
resolve `GERRIT_HOST`; stop and correct endpoint identity before continuing if
it does not.

Use the site-approved `LDAP_URL`. Use an `ldaps://` URL when directory policy
requires TLS and the directory exposes LDAPS.

The Gerrit runtime user and group are reviewed local OS identities. This
clean-install procedure creates them during installation. If your site uses
different names or numeric identities, substitute the reviewed values
consistently everywhere this manual shows the defaults.

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
- Confirm the reviewed Gerrit runtime account/group names, UID/GID, and product
  home are unused on the freshly provisioned host, then create them.
- Create and own `/srv/gerrit`, `/srv/gerrit/bin`, `/srv/gerrit/plugins`, and any
  staged `/var/lib/loopforge/staging/gerrit` content as documented.
- Place `/srv/gerrit/bin/gerrit.war`, initialize Gerrit as `gerrit`, and protect `/srv/gerrit/etc/secure.config`.
- Create `/etc/systemd/system/gerrit.service`, reload systemd, and start, stop, restart, or enable Gerrit.
- Run any `chown`, `chmod`, `apt`, `dpkg`, `systemctl`, or writes under `/etc`, `/opt`, or `/srv`.

A home-directory Gerrit process can be useful for lab validation, but it is not this production deployment. It will not match the documented systemd service management, ownership model, backup paths, or secret handling.

## 2. Dependencies and Gerrit Artifact Bundle

### 2.1 Install Ubuntu Dependencies

The package rationale and layered classification are maintained in
`docs/baselines/package-requirements.md`.

Run on the Gerrit host:

```bash
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  ldap-utils \
  openssh-client \
  openjdk-21-jre-headless \
  rsync \
  tar
java -version
```

Expected result: OpenJDK 21.

Prove that the reviewed LDAP bind account can search both configured bases.
Each command prompts for the LDAP bind password without placing it in shell
history. Stop if either command fails:

```bash
ldapsearch -x -H LDAP_URL -D LDAP_BIND_DN -W \
  -b LDAP_USER_BASE -s base dn
ldapsearch -x -H LDAP_URL -D LDAP_BIND_DN -W \
  -b LDAP_GROUP_BASE -s base dn
```

### 2.2 Create the Gerrit Artifact Bundle

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

Run on the bundle-factory VM. The owning bundle-factory prerequisite baseline
is defined in `docs/contracts/artifact-bundle-contract.md` and
`docs/baselines/package-requirements.md`. Verify the selected output paths are
fresh before creating the bundle. Stop and select a new bundle path if any
check fails:

```bash
test ! -e "$HOME/gerrit-artifacts-bundle"
test ! -e "$HOME/gerrit-artifacts-bundle.tar.gz"
test ! -e "$HOME/gerrit-artifacts-bundle.tar.gz.sha256"
mkdir -p "$HOME/gerrit-artifacts-bundle/gerrit"
cd "$HOME/gerrit-artifacts-bundle/gerrit"
wget -q --show-progress=off --tries=5 --timeout=30 --read-timeout=60 \
  -O gerrit-3.13.6.war \
  https://gerrit-releases.storage.googleapis.com/gerrit-3.13.6.war
```

Do not add external Gerrit plugin jars to the Loopforge Gerrit artifact bundle.
External plugins are operator-managed manual operations after Loopforge has
installed and validated core Gerrit.

Verify the Gerrit WAR archive:

```bash
cd "$HOME/gerrit-artifacts-bundle/gerrit"
unzip -t gerrit-3.13.6.war >/dev/null
```

Create the payload checksum and archive:

```bash
cd "$HOME/gerrit-artifacts-bundle/gerrit"
sha256sum gerrit-3.13.6.war > checksums.sha256
cd "$HOME"
tar -czf gerrit-artifacts-bundle.tar.gz -C gerrit-artifacts-bundle gerrit
sha256sum gerrit-artifacts-bundle.tar.gz \
  > gerrit-artifacts-bundle.tar.gz.sha256
```

The approved Gerrit release unit is the artifact archive and its `.sha256`
file.

### 2.3 Stage and Verify the Gerrit Artifact Bundle

Transfer the artifact archive and `.sha256` file to the operator's home on the
Gerrit host with approved media or an approved internal transfer path. Replace
the uppercase operator placeholders below with their reviewed values, then run
each command separately:

```bash
getent passwd LOOPFORGE_OPERATOR_ACCOUNT
getent group LOOPFORGE_OPERATOR_GROUP
cd "$HOME"
sha256sum -c gerrit-artifacts-bundle.tar.gz.sha256
sudo test ! -e /var/lib/loopforge/staging/gerrit
sudo install -d -m 0750 \
  -o LOOPFORGE_OPERATOR_ACCOUNT \
  -g LOOPFORGE_OPERATOR_GROUP \
  /var/lib/loopforge/staging
sudo tar -xzf gerrit-artifacts-bundle.tar.gz \
  -C /var/lib/loopforge/staging
sudo chown -R \
  LOOPFORGE_OPERATOR_ACCOUNT:LOOPFORGE_OPERATOR_GROUP \
  /var/lib/loopforge/staging/gerrit
cd /var/lib/loopforge/staging/gerrit
sha256sum -c checksums.sha256
```

The account and group lookups must return the reviewed operator identities,
both checksum commands must pass, and the staging freshness test must succeed.
Stop and reprovision the clean target if the Gerrit staging path already
exists; do not delete or repair it within this procedure. Staging does not
create the Gerrit runtime identity, product home, application state, or service
state.

## 3. Gerrit Installation and Configuration

### 3.1 Create the Runtime Identity and Product Home

This is a clean-install procedure. The four `getent` commands below must
return no entry, and the final `test` must succeed. If any reviewed name,
numeric ID, or path is already in use, stop and reprovision the target instead
of adapting or repairing it in place.

```bash
getent passwd gerrit
getent group gerrit
getent passwd 61010
getent group 61010
test ! -e /srv/gerrit
```

Create the runtime account and product home:

```bash
sudo groupadd --gid 61010 gerrit
sudo useradd --uid 61010 --gid 61010 --home-dir /srv/gerrit --no-create-home --shell /bin/bash gerrit
sudo install -d -m 0755 -o gerrit -g gerrit /srv/gerrit
```

Confirm the reviewed identity and product home:

```bash
getent passwd gerrit
getent group gerrit
test "$(getent passwd gerrit | cut -d: -f3)" = 61010
test "$(getent group gerrit | cut -d: -f3)" = 61010
test "$(getent passwd gerrit | cut -d: -f6)" = /srv/gerrit
test "$(stat -c '%U:%G' /srv/gerrit)" = gerrit:gerrit
```

### 3.2 Install the Gerrit WAR

Install the verified Gerrit WAR and create the initial role directories:

```bash
sudo install -d -o gerrit -g gerrit -m 0755 /srv/gerrit/bin
sudo cp /var/lib/loopforge/staging/gerrit/gerrit-3.13.6.war /srv/gerrit/bin/gerrit.war
sudo chown gerrit:gerrit /srv/gerrit/bin/gerrit.war
sudo install -d -o gerrit -g gerrit -m 0755 /srv/gerrit/plugins
sudo install -d -o gerrit -g gerrit -m 0750 /srv/gerrit/etc
```

If staging, extraction, checksum verification, or installation fails, preserve
bounded diagnostics and reprovision a fresh Gerrit target before starting a new
clean-install run. Do not overwrite or repair the selected staging or product
state in place. OS package-source failures belong to the approved internal
Ubuntu/OS package repository procedure.

The preceding role-local installation step placed the verified Gerrit WAR from
the staged bundle. Target hosts must not download Gerrit application artifacts
as fallback or replay the completed artifact installation here.

### 3.3 Initialize Gerrit

Run initialization as the `gerrit` user:

```bash
sudo -u gerrit java -jar /srv/gerrit/bin/gerrit.war init -d /srv/gerrit
```

Recommended answers:

- Git repositories: `/srv/gerrit/git`
- Index type: `lucene`
- Authentication method: `LDAP`
- HTTP daemon listen URL: `http://*:GERRIT_HTTP_PORT/`
- SSH daemon listen port: `GERRIT_SSH_PORT`
- Built-in plugin prompts: install only site-approved built-in plugins; keep
  plugin scope minimal.

For offline installation, do not allow `init` to fetch optional libraries from the internet unless the artifact was staged.

### 3.4 Configure Gerrit

Update the generated configuration with the reviewed values below:

```bash
sudoedit /srv/gerrit/etc/gerrit.config
```

Preserve the `serverId` created by Gerrit initialization; changing it after
NoteDb state exists makes that state unusable.

```ini
[gerrit]
  basePath = git
  canonicalWebUrl = GERRIT_CANONICAL_WEB_URL

[index]
  type = lucene

[auth]
  type = LDAP
  gitBasicAuthPolicy = HTTP_LDAP

[ldap]
  server = LDAP_URL
  username = LDAP_BIND_DN
  accountBase = LDAP_USER_BASE
  groupBase = LDAP_GROUP_BASE
  referral = follow

[httpd]
  listenUrl = http://*:GERRIT_HTTP_PORT/

[sshd]
  listenAddress = *:GERRIT_SSH_PORT

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

Protect the secure configuration before editing it, then store the LDAP bind
password:

```bash
sudo touch /srv/gerrit/etc/secure.config
sudo chown gerrit:gerrit /srv/gerrit/etc/secure.config
sudo chmod 0600 /srv/gerrit/etc/secure.config
sudoedit /srv/gerrit/etc/secure.config
```

```ini
[ldap]
  password = REPLACE_WITH_LDAP_BIND_PASSWORD
```

Set permissions:

```bash
sudo chown gerrit:gerrit /srv/gerrit/etc/gerrit.config
sudo chmod 0640 /srv/gerrit/etc/gerrit.config
sudo chown gerrit:gerrit /srv/gerrit/etc/secure.config
sudo chmod 0600 /srv/gerrit/etc/secure.config
```

### 3.5 Configure and Start the Gerrit Service

Create the unit with delegated privilege:

```bash
sudoedit /etc/systemd/system/gerrit.service
```

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
sudo systemctl daemon-reload
sudo systemctl enable --now gerrit
systemctl status gerrit
sudo journalctl -u gerrit -n 100 --no-pager
sudo tail -n 100 /srv/gerrit/logs/gerrit.log
```

Subsequent validation observes the enabled and active unit, its runtime owner,
the endpoints, LDAP, and bounded logs. It does not start or repair Gerrit.

## 4. Gerrit Role-Local Validation

Run:

```bash
java -version
systemctl is-enabled gerrit
systemctl is-active gerrit
systemctl show gerrit \
  --property=User --property=Group --property=MainPID --no-pager
curl -fsSI http://GERRIT_HOST:GERRIT_HTTP_PORT/
ssh-keyscan -T 5 -p GERRIT_SSH_PORT GERRIT_HOST
sudo tail -n 100 /srv/gerrit/logs/gerrit.log
```

`systemctl is-enabled` must report `enabled`, and `systemctl is-active` must
report `active`. The `systemctl show` output must report the reviewed Gerrit
runtime user and group and a nonzero `MainPID`. `curl` must return a successful
HTTP response, and `ssh-keyscan` must return Gerrit SSH host-key output from the
reviewed endpoint. Stop if any result differs.

Acceptance checks:

- OpenJDK 21 is active.
- Gerrit starts under systemd.
- LDAP users can log in.
- Gerrit SSH responds on `GERRIT_SSH_PORT`.
- Jenkins integration prerequisites from Section 6 are deferred to
  `docs/operations/native/integration.md`.

The reboot check is optional. To perform it, use the site's reviewed reboot
procedure, wait for the target to return, and rerun the validation above
without starting, enabling, or repairing Gerrit. Leave the optional checklist
item unchecked when the check is not performed. If the check is attempted and
Gerrit does not return to the same ready state, mark the run `BLOCKED`.

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

## 5. Site-Selected External Plugins, If Required

External Gerrit plugins are optional, operator-managed extensions. Loopforge
does not fetch, bundle, install, checksum, or validate external plugin jars as
part of baseline Gerrit role readiness or native acceptance. Use this section
only when the site requires plugins after Section 4 passes.

Common operator-selected plugins include:

- `events-log`: enables missed-event replay for Jenkins Gerrit Trigger.
- `metrics-reporter-prometheus`: exports operational metrics.
- `healthcheck`: provides optional health checks for monitoring.

Repository replication, outbound webhooks, ownership, HA, event-broker, and
issue-tracker plugins are deployment-specific operator choices.

### 5.1 Review Plugin Compatibility, Source, and Checksums

For each selected plugin, record its approved source, filename, version, and
SHA-256 checksum in the deployment change or ticket. The plugin must support
the selected Gerrit `3.13` major/minor line. Obtain it from an approved
internal mirror or reviewed artifact source, not as a target-host fallback
download.

Replace `PLUGIN_JAR` and `PLUGIN_SHA256` with the reviewed path and checksum,
then verify the selected artifact:

```bash
test -f PLUGIN_JAR
printf '%s  %s\n' PLUGIN_SHA256 PLUGIN_JAR | sha256sum -c -
```

Both commands must succeed. Stop if the artifact is absent, its checksum does
not match, or compatibility with Gerrit `3.13` has not been established. Keep
the plugin and its checksum outside the Loopforge Gerrit artifact bundle.

### 5.2 Install the Reviewed Plugins

Replace `PLUGIN_JAR` with the reviewed source path and `PLUGIN_FILENAME` with
the reviewed destination basename without `.jar`. Install each reviewed plugin
separately:

```bash
sudo install -d -m 0755 -o gerrit -g gerrit /srv/gerrit/plugins
sudo install -m 0644 -o gerrit -g gerrit \
  PLUGIN_JAR /srv/gerrit/plugins/PLUGIN_FILENAME.jar
sudo -u gerrit test -r /srv/gerrit/plugins/PLUGIN_FILENAME.jar
```

All commands must succeed before Gerrit is restarted. Do not overwrite an
existing plugin jar unless the deployment change explicitly reviews that
replacement as an upgrade.

### 5.3 Restart Gerrit

Restart Gerrit through its documented service control path, then inspect only
bounded service and application logs:

```bash
sudo systemctl restart gerrit
systemctl is-active gerrit
sudo journalctl -u gerrit -n 100 --no-pager
sudo tail -n 100 /srv/gerrit/logs/gerrit.log
```

`systemctl is-active` must report `active`. Stop before integration if either
bounded log reports a plugin load, compatibility, or startup failure. Use the
site-owned plugin cleanup or rollback procedure; do not hide recovery in this
installation branch.

### 5.4 Verify Plugin Loading

Sign in to `GERRIT_CANONICAL_WEB_URL` with the reviewed Gerrit administrator
account. Open the installed Gerrit UI's plugin administration page and confirm
each selected plugin is loaded at the reviewed version without an error or
disabled state.

Record site-selected plugin source, checksum, version, and load review in the
deployment change or ticket. Do not add plugin state to the Loopforge native
acceptance checklist or claim helper-equivalent plugin evidence.

## 6. Shared Integration Handoff

Gerrit-native baseline readiness stops before cross-role Jenkins integration.
Proceed only after Section 4 passes and, when Section 5 is selected, Section
5.4 also passes. The Gerrit role proves the Gerrit service, LDAP configuration,
HTTP endpoint, SSH endpoint, runtime account, staged artifacts, and bounded log
inspection. Baseline readiness does not require external Gerrit plugins.

This role does not register Jenkins public keys, create Gerrit Trigger
credentials, grant stream-events permission, apply `Verified` voting grants,
or prove trigger delivery. Later cross-role work belongs to the separate
integration workflow, which owns Jenkins-to-Gerrit public-key registration,
Gerrit integration permissions, `Verified` label/grant application,
stream-events validation, trigger validation, and integration acceptance. The
manual workflow is available in `docs/operations/native/integration.md`.

Credential custody remains fixed:

- The Jenkins controller owns the Jenkins-to-Gerrit private key.
- Gerrit consumes only the matching public key.
- Do not create a machine-generated Gerrit checkpoint-result file. Record the
  required
  role outcomes only in `docs/operations/native/acceptance-checklist.md`.
- Do not place private keys, passwords, tokens, LDAP bind secrets, or
  secret-bearing configuration in the checklist or its three references.

## 7. Backup and Operations

Treat the complete `/srv/gerrit` tree as the recovery unit. It includes Gerrit
configuration, repositories and NoteDb data, plugins, indexes, runtime data,
and the secret-bearing `etc/secure.config` file.

Before a backup, record:

- `GERRIT_BACKUP_ROOT`: approved protected local or mounted backup storage.
- `BACKUP_ID`: a unique timestamp or change identifier that does not already
  exist below `GERRIT_BACKUP_ROOT`.

Prefer a site-approved filesystem or storage snapshot that atomically covers
the complete Gerrit site. Retain the snapshot under the unique `BACKUP_ID` and
use the storage platform's native validation to confirm it is complete and
readable.

When a consistent snapshot is unavailable, schedule Gerrit downtime and copy
the stopped site. Run each command separately:

```bash
sudo systemctl stop gerrit
systemctl is-active gerrit
sudo test ! -e GERRIT_BACKUP_ROOT/gerrit-BACKUP_ID
sudo install -d -m 0700 -o root -g root \
  GERRIT_BACKUP_ROOT/gerrit-BACKUP_ID
sudo rsync -aHAX --numeric-ids \
  /srv/gerrit/ \
  GERRIT_BACKUP_ROOT/gerrit-BACKUP_ID/
sudo rsync -aHAXnc --delete --numeric-ids --itemize-changes \
  /srv/gerrit/ \
  GERRIT_BACKUP_ROOT/gerrit-BACKUP_ID/
sudo systemctl start gerrit
```

`systemctl is-active` must report `inactive` before the copy. The `test`
command must succeed so an existing backup is never overwritten. The checksum
comparison must produce no itemized changes. Stop and select storage that
preserves hard links, ACLs, extended attributes, and numeric ownership if
either `rsync` command reports an unsupported feature.

If copying or comparison fails, the backup failed. Start Gerrit, rerun all
Section 4 validation to end the outage safely, and investigate before the next
backup attempt. After a successful copy, start Gerrit and rerun the same
validation before closing the backup window.

Protect every backup with production-equivalent access restrictions and
encryption in transit and at rest. Retain multiple backup versions. Replicate
the completed local or mounted backup to remote storage only through the
site-approved protected transfer path; do not stream a live Gerrit site
directly to a remote destination.

Periodically prove that a backup can be restored in an isolated environment.
Use the matching Gerrit WAR, Java version, and reviewed plugin versions, keep
the isolated Gerrit service stopped while restoring the complete site, and
preserve the reviewed numeric runtime UID and GID. Verify ownership before
starting the isolated service, then run all Section 4 validation. Never test a
restore by overwriting an active production Gerrit site.

Upgrade principles:

- Back up before every upgrade.
- Test the target Gerrit WAR in staging.
- Rebuild the Gerrit artifact bundle and record checksums for every approved
  application artifact upgrade.
- If operators install external plugins, use jars built for the same Gerrit
  major/minor line and track their source approvals outside the Loopforge
  bundle.

## 8. References

- Jenkins controller native operations:
  `docs/operations/native/jenkins-controller.md`
- Integration native operations:
  `docs/operations/native/integration.md`
- Gerrit downloads: https://www.gerritcodereview.com/
- Gerrit support status: https://www.gerritcodereview.com/support.html
- Gerrit install documentation: https://gerrit-review.googlesource.com/Documentation/install.html
- Gerrit init command: https://gerrit-review.googlesource.com/Documentation/pgm-init.html
- Gerrit reverse proxy documentation: https://gerrit-review.googlesource.com/Documentation/config-reverseproxy.html
- Gerrit plugin documentation: https://gerrit-review.googlesource.com/Documentation/config-plugins.html
- Gerrit 3.14 release notes: https://gerrit.googlesource.com/homepage/+/refs/heads/master/pages/site/releases/3.14.md
- Gerrit 3.13 release notes: https://gerrit.googlesource.com/homepage/+/refs/heads/master/pages/site/releases/3.13.md
