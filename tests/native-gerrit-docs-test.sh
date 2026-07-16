#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
manual="$repo_root/docs/operations/native/gerrit.md"
directory_model="$repo_root/docs/contracts/directory-model.md"

require_text() {
  local pattern message
  pattern="${1:?pattern required}"
  message="${2:?message required}"
  grep -Fq -- "$pattern" "$manual" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

reject_text() {
  local pattern message
  pattern="${1:?pattern required}"
  message="${2:?message required}"
  if grep -Fq -- "$pattern" "$manual"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

reject_line() {
  local pattern message
  pattern="${1:?pattern required}"
  message="${2:?message required}"
  if grep -Fxq -- "$pattern" "$manual"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

heading_line() {
  local heading
  heading="${1:?heading required}"
  grep -n -m1 -Fx -- "$heading" "$manual" | cut -d: -f1
}

previous_heading_line=0
for heading in \
  '## 1. Operator Inputs and Preflight' \
  '### 1.1 If You Do Not Have Root Privileges' \
  '## 2. Dependencies and Gerrit Artifact Bundle' \
  '### 2.1 Install Ubuntu Dependencies' \
  '### 2.2 Create the Gerrit Artifact Bundle' \
  '### 2.3 Stage and Verify the Gerrit Artifact Bundle' \
  '## 3. Gerrit Installation and Configuration' \
  '### 3.1 Create the Runtime Identity and Product Home' \
  '### 3.2 Install the Gerrit WAR' \
  '### 3.3 Initialize Gerrit' \
  '### 3.4 Configure Gerrit' \
  '### 3.5 Configure and Start the Gerrit Service' \
  '## 4. Gerrit Role-Local Validation' \
  '## 5. Site-Selected External Plugins, If Required' \
  '### 5.1 Review Plugin Compatibility, Source, and Checksums' \
  '### 5.2 Install the Reviewed Plugins' \
  '### 5.3 Restart Gerrit' \
  '### 5.4 Verify Plugin Loading' \
  '## 6. Shared Integration Handoff' \
  '## 7. Backup and Operations' \
  '## 8. References'; do
  current_heading_line="$(heading_line "$heading")"
  [ -n "$current_heading_line" ] &&
    [ "$current_heading_line" -gt "$previous_heading_line" ] || {
    printf 'Native Gerrit heading is missing or out of order: %s\n' \
      "$heading" >&2
    exit 1
  }
  previous_heading_line="$current_heading_line"
done

for input in \
  'GERRIT_HOST' \
  'GERRIT_CANONICAL_WEB_URL' \
  'GERRIT_HTTP_PORT' \
  'GERRIT_SSH_PORT' \
  'LDAP_URL' \
  'LDAP_BIND_DN' \
  'LDAP_USER_BASE' \
  'LDAP_GROUP_BASE' \
  'GERRIT_ADMIN_ACCOUNT' \
  'GERRIT_ADMIN_GROUP' \
  'LOOPFORGE_OPERATOR_ACCOUNT' \
  'LOOPFORGE_OPERATOR_GROUP'; do
  require_text "$input" "Native Gerrit input is missing: $input"
done
require_text 'clean-install procedure creates them during installation.' \
  'Native Gerrit procedure must leave runtime identity creation to installation'
reject_text 'Create or confirm' \
  'Native Gerrit inputs must not pre-create the role-owned runtime identity'

require_text 'sudo apt update' \
  'Native Gerrit dependency installation must use delegated privilege'
require_text 'sudo apt install -y' \
  'Native Gerrit package installation must use delegated privilege'
require_text '  ldap-utils \' \
  'Native Gerrit target must install the LDAP proof utility'
require_text 'ldapsearch -x -H LDAP_URL -D LDAP_BIND_DN -W \' \
  'Native Gerrit procedure must perform an LDAP bind/search proof'

reject_text 'command -v ' \
  'Native Gerrit bundle preparation must not repeat installed-package probes'

for freshness_check in \
  'test ! -e "$HOME/gerrit-artifacts-bundle"' \
  'test ! -e "$HOME/gerrit-artifacts-bundle.tar.gz"' \
  'test ! -e "$HOME/gerrit-artifacts-bundle.tar.gz.sha256"' \
  'sudo test ! -e /var/lib/loopforge/staging/gerrit' \
  'test ! -e /srv/gerrit'; do
  require_text "$freshness_check" \
    "Native Gerrit procedure must require fresh selected state: $freshness_check"
done

require_text 'sha256sum gerrit-3.13.6.war > checksums.sha256' \
  'Native Gerrit payload must checksum the reviewed WAR directly'
require_text 'sha256sum -c checksums.sha256' \
  'Native Gerrit staging must verify the payload checksum'

staging_section="$(
  sed -n \
    '/^### 2\.3 Stage and Verify the Gerrit Artifact Bundle$/,/^## 3\. Gerrit Installation and Configuration$/p' \
    "$manual"
)"
for staging_check in \
  'each command separately:' \
  'getent passwd LOOPFORGE_OPERATOR_ACCOUNT' \
  'getent group LOOPFORGE_OPERATOR_GROUP' \
  'cd "$HOME"' \
  'sha256sum -c gerrit-artifacts-bundle.tar.gz.sha256' \
  'sudo test ! -e /var/lib/loopforge/staging/gerrit' \
  'LOOPFORGE_OPERATOR_ACCOUNT:LOOPFORGE_OPERATOR_GROUP' \
  'sha256sum -c checksums.sha256'; do
  printf '%s\n' "$staging_section" | grep -Fq -- "$staging_check" || {
    printf 'Native Gerrit staging checkpoint is missing: %s\n' \
      "$staging_check" >&2
    exit 1
  }
done
for helper_like_staging_logic in \
  'operator_account=' \
  'operator_group=' \
  'operator_home=' \
  'java -version'; do
  if printf '%s\n' "$staging_section" | grep -Fq -- "$helper_like_staging_logic"; then
    printf 'Native Gerrit staging must remain operator-first: %s\n' \
      "$helper_like_staging_logic" >&2
    exit 1
  fi
done
for runtime_mutation in \
  'sudo groupadd' \
  'sudo useradd' \
  '/srv/gerrit/bin/gerrit.war' \
  'sudo systemctl'; do
  if printf '%s\n' "$staging_section" | grep -Fq -- "$runtime_mutation"; then
    printf 'Native Gerrit staging must not perform runtime mutation: %s\n' \
      "$runtime_mutation" >&2
    exit 1
  fi
done

identity_line="$(grep -n -m1 'sudo groupadd --gid 61010 gerrit' "$manual" | cut -d: -f1)"
war_line="$(grep -n -m1 'sudo cp /var/lib/loopforge/staging/gerrit/gerrit-3.13.6.war' "$manual" | cut -d: -f1)"
init_line="$(grep -n -m1 'sudo -u gerrit java -jar /srv/gerrit/bin/gerrit.war init' "$manual" | cut -d: -f1)"
config_line="$(grep -n -m1 'sudoedit /srv/gerrit/etc/gerrit.config' "$manual" | cut -d: -f1)"
service_line="$(grep -n -m1 'sudoedit /etc/systemd/system/gerrit.service' "$manual" | cut -d: -f1)"
validation_line="$(heading_line '## 4. Gerrit Role-Local Validation')"
[ "$identity_line" -lt "$war_line" ] &&
  [ "$war_line" -lt "$init_line" ] &&
  [ "$init_line" -lt "$config_line" ] &&
  [ "$config_line" -lt "$service_line" ] &&
  [ "$service_line" -lt "$validation_line" ] || {
  printf 'Native Gerrit installation operations are out of lifecycle order\n' >&2
  exit 1
}

reject_text 'gerrit/manifest.txt' \
  'Native Gerrit payload must not require a helper manifest'
reject_text 'harness_manifest_version' \
  'Native Gerrit payload must not copy the helper manifest schema'
reject_text 'template_count=' \
  'Native Gerrit payload must not claim helper templates'
grep -Fq -- \
  'Gerrit WAR and checksums; helper payloads also carry templates and a manifest' \
  "$directory_model" || {
  printf 'Directory authority must distinguish native and helper Gerrit payloads\n' >&2
  exit 1
}
reject_text 'rm -rf' \
  'Native Gerrit setup must not clean stale selected state in place'
reject_text 'For artifact recovery, rerun' \
  'Native Gerrit setup must not hide artifact recovery in the install path'

require_text 'sudoedit /srv/gerrit/etc/gerrit.config' \
  'Native Gerrit configuration must use delegated privilege'
require_text '  server = LDAP_URL' \
  'Native Gerrit configuration must use the reviewed LDAP URL'
require_text '  listenUrl = http://*:GERRIT_HTTP_PORT/' \
  'Native Gerrit configuration must use the reviewed HTTP port'
require_text '  listenAddress = *:GERRIT_SSH_PORT' \
  'Native Gerrit configuration must use the reviewed SSH port'
require_text 'Preserve the `serverId` created by Gerrit initialization' \
  'Native Gerrit configuration must preserve the generated server ID'
reject_text 'REPLACE_WITH_GENERATED_OR_STABLE_UUID' \
  'Native Gerrit configuration must not contain an unresolved server ID'
reject_line 'cp /var/lib/loopforge/staging/gerrit/gerrit-3.13.6.war /srv/gerrit/bin/gerrit.war' \
  'Native Gerrit installation must not replay an unprivileged WAR copy'

for privileged_command in \
  'sudo systemctl daemon-reload' \
  'sudo systemctl enable --now gerrit' \
  'sudo chown gerrit:gerrit /srv/gerrit/etc/gerrit.config' \
  'sudo chmod 0600 /srv/gerrit/etc/secure.config' \
  'sudo install -m 0644 -o gerrit -g gerrit'; do
  require_text "$privileged_command" \
    "Native Gerrit delegated operation is missing: $privileged_command"
done

for validation_check in \
  'systemctl show gerrit \' \
  '--property=User --property=Group --property=MainPID --no-pager' \
  'curl -fsSI http://GERRIT_HOST:GERRIT_HTTP_PORT/' \
  'ssh-keyscan -T 5 -p GERRIT_SSH_PORT GERRIT_HOST'; do
  require_text "$validation_check" \
    "Native Gerrit validation is missing: $validation_check"
done
reject_text 'USER@GERRIT_HOST' \
  'Native Gerrit role validation must not require an unprovisioned SSH account'

for plugin_contract in \
  'External Gerrit plugins are optional, operator-managed extensions.' \
  'approved source, filename, version, and' \
  "printf '%s  %s\\n' PLUGIN_SHA256 PLUGIN_JAR | sha256sum -c -" \
  'sudo install -m 0644 -o gerrit -g gerrit \' \
  'sudo systemctl restart gerrit' \
  "installed Gerrit UI's plugin administration page" \
  'Do not add plugin state to the Loopforge native'; do
  require_text "$plugin_contract" \
    "Native Gerrit optional plugin branch is missing: $plugin_contract"
done
reject_text 'repeat all Section 4 validation' \
  'Native Gerrit plugin verification must not repeat role-local validation'
require_text 'Proceed only after Section 4 passes and, when Section 5 is selected,' \
  'Native Gerrit integration handoff must follow baseline and selected plugin validation'
require_text 'Jenkins integration prerequisites from Section 6 are deferred to' \
  'Native Gerrit validation must point to the renumbered integration handoff'

for backup_contract in \
  'Treat the complete `/srv/gerrit` tree as the recovery unit.' \
  'Prefer a site-approved filesystem or storage snapshot that atomically covers' \
  'sudo systemctl stop gerrit' \
  'sudo test ! -e GERRIT_BACKUP_ROOT/gerrit-BACKUP_ID' \
  'sudo rsync -aHAX --numeric-ids' \
  'sudo rsync -aHAXnc --delete --numeric-ids --itemize-changes' \
  'Periodically prove that a backup can be restored in an isolated environment.' \
  'by overwriting an active production Gerrit site.'; do
  require_text "$backup_contract" \
    "Native Gerrit backup contract is missing: $backup_contract"
done

printf 'Native Gerrit documentation contract passed\n'
