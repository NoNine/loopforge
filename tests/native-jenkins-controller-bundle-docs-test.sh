#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
manual="$repo_root/docs/operations/native/jenkins-controller.md"
setup_manual="$repo_root/docs/operations/setup/jenkins-controller.md"
bundle_contract="$repo_root/docs/contracts/artifact-bundle-contract.md"
checklist="$repo_root/docs/operations/native/acceptance-checklist.md"

require_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  grep -Fq -- "$pattern" "$file" || {
    printf '%s\n' "$message" >&2
    exit 1
  }
}

reject_text() {
  local file pattern message
  file="${1:?file required}"
  pattern="${2:?pattern required}"
  message="${3:?message required}"
  if grep -Fq -- "$pattern" "$file"; then
    printf '%s\n' "$message" >&2
    exit 1
  fi
}

heading_line() {
  local heading
  heading="${1:?heading required}"
  grep -n -m1 -Fx -- "$heading" "$manual" | cut -d: -f1
}

require_text \
  "$manual" \
  'mkdir -p "$HOME/jenkins-artifacts-bundle/jenkins"' \
  'Native Jenkins preparation must create the archived payload directly'
require_text \
  "$manual" \
  'cd ~/jenkins-artifacts-bundle/jenkins' \
  'Native Jenkins preparation must download artifacts into the archived payload'
require_text \
  "$manual" \
  'java -jar ~/jenkins-artifacts-bundle/jenkins/jenkins-plugin-manager-2.15.0.jar' \
  'Native Jenkins plugin resolution must use the archived plugin manager'
require_text \
  "$manual" \
  'The Plugin Installation Manager remains a bundle-factory' \
  'Native Jenkins must keep the plugin manager outside runtime state'
reject_text \
  "$manual" \
  '/var/lib/jenkins/war/jenkins-plugin-manager.jar' \
  'Native Jenkins must not install the plugin manager into runtime state'
require_text \
  "$setup_manual" \
  'prepared and staged bundle for plugin resolution provenance' \
  'Jenkins setup documentation must retain plugin manager provenance'
require_text \
  "$setup_manual" \
  'into Jenkins runtime state.' \
  'Jenkins setup documentation must keep the plugin manager bundle-factory only'
reject_text \
  "$setup_manual" \
  '`war/jenkins-plugin-manager.jar`' \
  'Jenkins setup documentation must not claim a runtime plugin manager output'
reject_text \
  "$manual" \
  'jenkins-artifacts-bundle/tools' \
  'Native Jenkins preparation must not leave the plugin manager outside the archive'
require_text \
  "$manual" \
  'Create checksums and archive:' \
  'Native Jenkins preparation must create its payload checksum directly'
require_text \
  "$manual" \
  'sha256sum jenkins-artifacts-bundle.tar.gz' \
  'Native Jenkins archive checksum must use the transferable basename'
reject_text \
  "$manual" \
  'sha256sum ~/jenkins-artifacts-bundle.tar.gz' \
  'Native Jenkins archive checksum must not record a bundle-factory absolute path'
for pattern in \
  'jenkins/manifest.txt' \
  'harness_manifest_version' \
  'template_count=' \
  '/var/lib/loopforge/staging/jenkins/templates' \
  'controller templates'; do
  reject_text \
    "$manual" \
    "$pattern" \
    "Native Jenkins preparation must not require helper metadata or templates: $pattern"
done
require_text \
  "$bundle_contract" \
  'Each helper-generated payload must contain exactly one compact `manifest.txt`' \
  'Artifact contract must retain helper-generated manifests'
require_text \
  "$bundle_contract" \
  'The native operation reference defines its remaining' \
  'Artifact contract must assign native payload contents to the native reference'
require_text \
  "$bundle_contract" \
  'native payloads do not inherit helper manifest or template' \
  'Artifact contract must separate native payloads from helper metadata'
require_text \
  "$bundle_contract" \
  'its procedure uses them.' \
  'Artifact contract must allow procedure-owned native manifests or templates'
require_text \
  "$checklist" \
  'Reviewed artifact inventories and checksums match the artifacts staged on' \
  'Native acceptance must review artifact inventories without requiring manifests'

previous_heading_line=0
for heading in \
  '## 1. Operator Inputs and Preflight' \
  '### 1.1 If You Do Not Have Root Privileges' \
  '## 2. Dependencies and Jenkins Controller Artifact Bundle' \
  '### 2.1 Install Ubuntu Dependencies' \
  '### 2.2 Create the Controller Artifact Bundle' \
  '### 2.3 Stage and Verify the Controller Artifact Bundle' \
  '## 3. Jenkins Controller Installation and Configuration' \
  '### 3.1 Create the Runtime Identity and Product Home' \
  '### 3.2 Install the Jenkins WAR' \
  '### 3.3 Configure the Jenkins Service' \
  '### 3.4 Install Jenkins Plugins' \
  '### 3.5 Configure the JCasC Baseline' \
  '### 3.6 Start Jenkins' \
  '## 4. Jenkins Controller Role-Local Validation' \
  '## 5. Add Additional Jenkins Administrators' \
  '### 5.1 Review the Additional LDAP Administrator Accounts' \
  '### 5.2 Grant Jenkins Administrator Access in the UI' \
  '### 5.3 Synchronize the JCasC Administrator Entries' \
  '### 5.4 Verify Administrator Access After Restart' \
  '## 6. Shared Integration Handoff' \
  '### 6.1 Outbound SSH Build Agent Inputs' \
  '## 7. Backup and Operations' \
  '## 8. References'; do
  current_heading_line="$(heading_line "$heading")"
  [ -n "$current_heading_line" ] &&
    [ "$current_heading_line" -gt "$previous_heading_line" ] || {
    printf 'Native Jenkins heading is missing or out of order: %s\n' \
      "$heading" >&2
    exit 1
  }
  previous_heading_line="$current_heading_line"
done

for pattern in \
  'plugins/*.{hpi,jpi}' \
  'systemctl stop jenkins || true' \
  'systemctl enable --now jenkins' \
  'prometheusConfiguration' \
  'prometheus.jpi' \
  'name: "jenkins-admins"' \
  'name: "gerrit-ci-users"' \
  'reviewed Jenkins administrator group' \
  'BACKUP_HOST:/backups/jenkins/' \
  '| Gerrit host |' \
  '| Gerrit HTTP port |' \
  '| Gerrit SSH port |' \
  '| Jenkins Gerrit integration account |' \
  'getent hosts JENKINS_HOST GERRIT_HOST' \
  'nc -vz GERRIT_HOST' \
  '--httpPort=8080' \
  'server: "ldap://LDAP_HOST:389"' \
  'url: "http://JENKINS_HOST:8080/"' \
  '|| true' \
  'lsb_release -a' \
  'ip addr' \
  'ip route' \
  'apt policy' \
  'dpkg -l' \
  'ss -lntup' \
  'nc -vz' \
  'operator_account=' \
  'operator_group=' \
  'operator_home=' \
  'rm -rf' \
  'UI-Driven Configuration Fallback' \
  'initialAdminPassword' \
  'setup-wizard administrator' \
  'remove the `CASC_JENKINS_CONFIG`' \
  "if grep -q '[[:space:]]'" \
  'Controller-only bringup stops before cross-role Gerrit and agent integration.' \
  'Later cross-role work belongs to' \
  'The manual integration workflow is available' \
  'checklist or its three references' \
  'gerrit-code-review'; do
  reject_text \
    "$manual" \
    "$pattern" \
    "Native Jenkins lifecycle must not retain masked or duplicate behavior: $pattern"
done

require_text \
  "$manual" \
  '| Jenkins browser URL | `JENKINS_URL`, reviewed browser-visible root URL |' \
  'Native Jenkins inputs must record the reviewed browser-visible URL'
require_text \
  "$manual" \
  '| HTTP port | `JENKINS_HTTP_PORT`, default `8080` |' \
  'Native Jenkins inputs must record the reviewed HTTP port'
require_text \
  "$manual" \
  '| LDAP URL | `LDAP_URL`, for example `ldap://LDAP_HOST:389` or `ldaps://LDAP_HOST:636` |' \
  'Native Jenkins inputs must record the reviewed LDAP endpoint'
require_text \
  "$manual" \
  '| LDAP root DN | `LDAP_ROOT_DN`, or empty when using absolute search bases |' \
  'Native Jenkins inputs must record the LDAP root-DN decision'
require_text \
  "$manual" \
  '| Jenkins runtime UID | `JENKINS_RUNTIME_UID`, default `61020` |' \
  'Native Jenkins inputs must record the reviewed runtime UID'
require_text \
  "$manual" \
  '| Jenkins runtime GID | `JENKINS_RUNTIME_GID`, default `61020` |' \
  'Native Jenkins inputs must record the reviewed runtime GID'
require_text \
  "$manual" \
  '| Operator account | `LOOPFORGE_OPERATOR_ACCOUNT`, default `ci-operator` |' \
  'Native Jenkins inputs must record the reviewed operator account'
require_text \
  "$manual" \
  '| Operator group | `LOOPFORGE_OPERATOR_GROUP`, default `ci-operator` |' \
  'Native Jenkins inputs must record the reviewed operator group'
require_text \
  "$manual" \
  $'cat /etc/os-release\nhostnamectl\ntimedatectl\ndf -h /var/lib\nfree -h\nsystemctl --failed\ngetent hosts JENKINS_HOST' \
  'Native Jenkins preflight must remain concise and independently runnable'
require_text \
  "$manual" \
  'must resolve `JENKINS_HOST`; stop and correct host identity before continuing' \
  'Native Jenkins preflight must state its host-resolution stop condition'
require_text \
  "$manual" \
  'sudo apt update' \
  'Native Jenkins dependency installation must use delegated privilege'
require_text \
  "$manual" \
  'sudo apt install -y' \
  'Native Jenkins package installation must use delegated privilege'
for fresh_path in \
  'test ! -e "$HOME/jenkins-artifacts-bundle"' \
  'test ! -e "$HOME/jenkins-artifacts-bundle.tar.gz"' \
  'test ! -e "$HOME/jenkins-artifacts-bundle.tar.gz.sha256"'; do
  require_text \
    "$manual" \
    "$fresh_path" \
    "Native Jenkins preparation must require fresh selected state: $fresh_path"
done
require_text \
  "$manual" \
  'mkdir ~/jenkins-artifacts-bundle/jenkins/plugins' \
  'Native Jenkins preparation must create the plugin destination once'
require_text \
  "$manual" \
  'sha256sum jenkins-plugin-manager-2.15.0.jar' \
  'Native Jenkins preparation must display the Plugin Manager artifact checksum'
require_text \
  "$manual" \
  'cat jenkins-plugin-manager-2.15.0.jar.sha256' \
  'Native Jenkins preparation must display the published Plugin Manager checksum'
require_text \
  "$manual" \
  'The two displayed 64-character hashes must match exactly.' \
  'Native Jenkins preparation must state the visual checksum decision'
require_text \
  "$manual" \
  'getent passwd LOOPFORGE_OPERATOR_ACCOUNT' \
  'Native Jenkins staging must validate the reviewed operator account'
require_text \
  "$manual" \
  'getent group LOOPFORGE_OPERATOR_GROUP' \
  'Native Jenkins staging must validate the reviewed operator group'
require_text \
  "$manual" \
  'sudo test ! -e /var/lib/loopforge/staging/jenkins' \
  'Native Jenkins staging must fail for existing selected state'
require_text \
  "$manual" \
  'LOOPFORGE_OPERATOR_ACCOUNT:LOOPFORGE_OPERATOR_GROUP' \
  'Native Jenkins staging must apply the reviewed operator ownership'

staging_section="$(
  sed -n \
    '/^### 2\.3 Stage and Verify the Controller Artifact Bundle$/,/^## 3\. Jenkins Controller Installation and Configuration$/p' \
    "$manual"
)"
for staging_check in \
  'each command separately:' \
  'sha256sum -c jenkins-artifacts-bundle.tar.gz.sha256' \
  'sudo test ! -e /var/lib/loopforge/staging/jenkins' \
  'sha256sum -c checksums.sha256'; do
  grep -Fq -- "$staging_check" <<<"$staging_section" || {
    printf 'Native Jenkins staging checkpoint is missing: %s\n' \
      "$staging_check" >&2
    exit 1
  }
done
for runtime_mutation in \
  'sudo groupadd' \
  'sudo useradd' \
  '/var/lib/jenkins/war' \
  'sudo systemctl'; do
  if grep -Fq -- "$runtime_mutation" <<<"$staging_section"; then
    printf 'Native Jenkins staging must not perform runtime mutation: %s\n' \
      "$runtime_mutation" >&2
    exit 1
  fi
done

require_text \
  "$manual" \
  'Complete Section 4 before integration.' \
  'Native Jenkins handoff must require role-local validation'
require_text \
  "$manual" \
  'When Section 5 is selected, complete' \
  'Native Jenkins handoff must require selected administrator verification'
require_text \
  "$manual" \
  'secret-bearing configuration in the checklist or referenced native manuals.' \
  'Native Jenkins handoff must state the manual redaction boundary'
require_text \
  "$manual" \
  'Replace every uppercase placeholder with its reviewed value before saving:' \
  'Native Jenkins systemd instructions must require placeholder replacement'
require_text \
  "$manual" \
  '--httpPort=JENKINS_HTTP_PORT' \
  'Native Jenkins systemd must use the reviewed HTTP port'
require_text \
  "$manual" \
  'server: "LDAP_URL"' \
  'Native Jenkins JCasC must use the reviewed LDAP endpoint'
require_text \
  "$manual" \
  'url: "JENKINS_URL"' \
  'Native Jenkins JCasC must use the reviewed browser-visible URL'
require_text \
  "$manual" \
  'http://JENKINS_HOST:JENKINS_HTTP_PORT/' \
  'Native Jenkins direct endpoint operations must use the reviewed service port'
require_text \
  "$manual" \
  'systemctl show jenkins --property=User --property=Group --property=MainPID --no-pager' \
  'Native Jenkins validation must inspect the systemd runtime identity and process'
require_text \
  "$manual" \
  'runtime user and group and a nonzero `MainPID`' \
  'Native Jenkins validation must state the runtime identity stop condition'
require_text \
  "$manual" \
  'Treat the complete `/var/lib/jenkins` tree as the recovery unit.' \
  'Native Jenkins backup must cover the complete Jenkins home'
require_text \
  "$manual" \
  'Prefer a site-approved filesystem or storage snapshot that atomically covers' \
  'Native Jenkins backup must prefer a consistent snapshot'
require_text \
  "$manual" \
  'sudo systemctl stop jenkins' \
  'Native Jenkins backup fallback must stop the controller before copying'
require_text \
  "$manual" \
  'sudo test ! -e JENKINS_BACKUP_ROOT/jenkins-BACKUP_ID' \
  'Native Jenkins backup must not overwrite an existing backup'
require_text \
  "$manual" \
  'sudo rsync -aHAX --numeric-ids' \
  'Native Jenkins backup must preserve filesystem metadata and numeric ownership'
require_text \
  "$manual" \
  'sudo rsync -aHAXnc --delete --numeric-ids --itemize-changes' \
  'Native Jenkins backup must checksum-compare the stopped copy'
require_text \
  "$manual" \
  'Periodically prove that a backup can be restored in an isolated environment.' \
  'Native Jenkins backup must require isolated restore testing'
require_text \
  "$manual" \
  'by overwriting an active production Jenkins home.' \
  'Native Jenkins restore testing must not overwrite active production state'

require_text \
  "$manual" \
  $'        - user:\n            name: "LDAP_ADMIN_USER"\n            permissions:\n              - "Overall/Administer"' \
  'Native Jenkins authorization must use a site-specific LDAP administrator user'
require_text \
  "$manual" \
  $'        - group:\n            name: "authenticated"\n            permissions:\n              - "Overall/Read"\n              - "Job/Read"\n              - "Job/Build"' \
  'Native Jenkins authorization must grant authenticated LDAP users read and build access'

require_text \
  "$manual" \
  'JCasC is the required baseline configuration path' \
  'Native Jenkins installation must always configure the JCasC baseline'
require_text \
  "$manual" \
  'UI-only changes to those fields are not durable.' \
  'Native Jenkins must identify the JCasC ownership boundary'

administrator_section="$(
  sed -n \
    '/^## 5\. Add Additional Jenkins Administrators$/,/^## 6\. Shared Integration Handoff$/p' \
    "$manual"
)"
for administrator_contract in \
  'reviewed LDAP-backed human' \
  'Overall/Administer' \
  'Preserve the original `LDAP_ADMIN_USER` entry' \
  'Overall/Read' \
  'Job/Read' \
  'Job/Build' \
  'Do not change the LDAP security realm' \
  'sudoedit /var/lib/jenkins/jcasc/jenkins.yaml' \
  'ADDITIONAL_LDAP_ADMIN_USER' \
  'sudo chmod 0600 /var/lib/jenkins/jcasc/jenkins.yaml' \
  'Check Configuration' \
  'sudo systemctl restart jenkins' \
  'do not rerun Section 4'; do
  grep -Fq -- "$administrator_contract" <<<"$administrator_section" || {
    printf 'Native Jenkins administrator operation is missing: %s\n' \
      "$administrator_contract" >&2
    exit 1
  }
done

require_text \
  "$manual" \
  '/var/lib/loopforge/staging/jenkins/plugins/*.jpi' \
  'Native Jenkins must install the Plugin Manager generated JPI set'

identity_line="$(grep -n -m1 'sudo groupadd --gid 61020 jenkins' "$manual" | cut -d: -f1)"
war_line="$(grep -n -m1 '/var/lib/loopforge/staging/jenkins/jenkins-2.555.3.war' "$manual" | cut -d: -f1)"
enable_line="$(grep -n -m1 'sudo systemctl enable jenkins' "$manual" | cut -d: -f1)"
plugins_line="$(grep -n -m1 '/var/lib/loopforge/staging/jenkins/plugins/\*.jpi' "$manual" | cut -d: -f1)"
jcasc_line="$(grep -n -m1 'sudoedit /var/lib/jenkins/jcasc/jenkins.yaml' "$manual" | cut -d: -f1)"
start_line="$(grep -n -m1 'sudo systemctl start jenkins' "$manual" | cut -d: -f1)"
validation_line="$(heading_line '## 4. Jenkins Controller Role-Local Validation')"
administrators_line="$(heading_line '## 5. Add Additional Jenkins Administrators')"
handoff_line="$(heading_line '## 6. Shared Integration Handoff')"
[ "$identity_line" -lt "$war_line" ] &&
  [ "$war_line" -lt "$enable_line" ] &&
  [ "$enable_line" -lt "$plugins_line" ] &&
  [ "$plugins_line" -lt "$jcasc_line" ] &&
  [ "$jcasc_line" -lt "$start_line" ] &&
  [ "$start_line" -lt "$validation_line" ] &&
  [ "$validation_line" -lt "$administrators_line" ] &&
  [ "$administrators_line" -lt "$handoff_line" ] || {
  printf 'Native Jenkins lifecycle operations are out of order\n' >&2
  exit 1
}
startup_section="$(
  sed -n \
    '/^### 3.6 Start Jenkins$/,/^## 4. Jenkins Controller Role-Local Validation$/p' \
    "$manual"
)"
[ "$(printf '%s\n' "$startup_section" | grep -Fc 'sudo systemctl start jenkins')" -eq 1 ] || {
  printf 'Native Jenkins lifecycle must start Jenkins exactly once\n' >&2
  exit 1
}

printf 'Native Jenkins controller bundle documentation contract passed\n'
