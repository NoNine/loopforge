#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
manual="$repo_root/docs/operations/native/jenkins-agent.md"
setup_manual="$repo_root/docs/operations/setup/jenkins-agent.md"
integration="$repo_root/docs/operations/native/integration.md"
prd="$repo_root/docs/product/prd.md"
system_model="$repo_root/docs/architecture/system-model.md"
lifecycle="$repo_root/docs/contracts/lifecycle-contract.md"
operator_contract="$repo_root/docs/contracts/operator-execution-contract.md"
review_guide="$repo_root/docs/operations/native/review-guide.md"
step_plan="$repo_root/docs/planning/steps/step-09-jenkins-agent-manual-and-helper.md"

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

for input in \
  'JENKINS_AGENT_HOST' \
  'JENKINS_AGENT_SSH_PORT' \
  'JENKINS_AGENT_UID' \
  'JENKINS_AGENT_GID' \
  'LOOPFORGE_OPERATOR_ACCOUNT' \
  'LOOPFORGE_OPERATOR_GROUP'; do
  require_text "$manual" "$input" "Native agent input is missing: $input"
done

for subsection in \
  '### 2.1 Install Ubuntu Dependencies' \
  '### 2.2 Create the Agent Artifact Bundle' \
  '### 2.3 Stage and Verify the Agent Artifact Bundle'; do
  require_text "$manual" "$subsection" \
    "Native agent Section 2 is missing the ordered step: $subsection"
done

require_text "$manual" \
  '| Agent runtime user | `jenkins-agent`, local OS account |' \
  'Native agent procedure must use the baseline runtime account'
require_text "$manual" \
  '| Agent runtime group | `jenkins-agent`, local OS group |' \
  'Native agent procedure must use the baseline runtime group'
require_text "$manual" \
  'The native baseline runtime account and group are' \
  'Native agent procedure must identify jenkins-agent as the baseline identity'
require_text "$manual" \
  'substitute the reviewed name' \
  'Native agent procedure must allow consistent reviewed site identity substitution'
for native_identity_doc in "$manual" "$integration"; do
  reject_text "$native_identity_doc" \
    'JENKINS_AGENT_ACCOUNT' \
    'Native procedures must not expose a configurable agent account name'
  reject_text "$native_identity_doc" \
    'JENKINS_AGENT_GROUP' \
    'Native procedures must not expose a configurable agent group name'
done

require_text "$manual" \
  'The product home remains' \
  'Native agent procedure must keep the canonical product home'
require_text "$manual" \
  $'cat /etc/os-release\nhostnamectl\ntimedatectl\ndf -h /var/lib\nfree -h\nsystemctl --failed\ngetent hosts JENKINS_AGENT_HOST' \
  'Native agent preflight must remain concise and operator-first'
require_text "$manual" \
  'stop and correct endpoint identity if it does not.' \
  'Native agent preflight must define the host-resolution stop condition'

for freshness_check in \
  'test ! -e "$HOME/jenkins-agent-artifacts-bundle"' \
  'test ! -e "$HOME/jenkins-agent-artifacts-bundle.tar.gz"' \
  'test ! -e "$HOME/jenkins-agent-artifacts-bundle.tar.gz.sha256"' \
  'sudo test ! -e /var/lib/loopforge/staging/jenkins-agent' \
  'test ! -e /var/lib/jenkins-agent' \
  'sudo test ! -e /etc/ssh/sshd_config.d/40-jenkins-agent.conf'; do
  require_text "$manual" "$freshness_check" \
    "Native agent procedure must require fresh selected state: $freshness_check"
done

require_text "$manual" \
  'sha256sum jenkins-agent-artifacts-bundle.tar.gz' \
  'Native agent archive checksum must use the transferable basename'
require_text "$manual" \
  $'cd /var/lib/loopforge/staging/jenkins-agent\nsha256sum -c checksums.sha256' \
  'Native agent staging must verify payload checksums before mutation'

staging_section="$(
  sed -n \
    '/^### 2\.3 Stage and Verify the Agent Artifact Bundle$/,/^## 3\. Jenkins Agent Installation and Configuration$/p' \
    "$manual"
)"
for staging_check in \
  'each command separately:' \
  'getent passwd LOOPFORGE_OPERATOR_ACCOUNT' \
  'getent group LOOPFORGE_OPERATOR_GROUP' \
  'sha256sum -c jenkins-agent-artifacts-bundle.tar.gz.sha256' \
  'sudo test ! -e /var/lib/loopforge/staging/jenkins-agent' \
  'LOOPFORGE_OPERATOR_ACCOUNT:LOOPFORGE_OPERATOR_GROUP' \
  'sha256sum -c checksums.sha256'; do
  grep -Fq -- "$staging_check" <<<"$staging_section" || {
    printf 'Native agent staging checkpoint is missing: %s\n' \
      "$staging_check" >&2
    exit 1
  }
done
for runtime_mutation in \
  'sudo groupadd' \
  'sudo useradd' \
  '/var/lib/jenkins-agent' \
  '/etc/ssh/sshd_config.d/40-jenkins-agent.conf' \
  'sudo systemctl'; do
  if grep -Fq -- "$runtime_mutation" <<<"$staging_section"; then
    printf 'Native agent staging must not perform runtime mutation: %s\n' \
      "$runtime_mutation" >&2
    exit 1
  fi
done

reject_text "$manual" \
  'harness_manifest_version' \
  'Native agent payload must not copy the helper manifest schema'
reject_text "$manual" \
  'template_count=' \
  'Native agent payload must not claim helper templates'
reject_text "$manual" \
  'JENKINS_BUILD_EXTRA_PACKAGES' \
  'Native agent procedure must not expose an unused package variable'
reject_text "$manual" \
  'rm -rf' \
  'Native agent procedure must not clean selected state inside setup'
reject_text "$manual" \
  '|| true' \
  'Native agent procedure must not mask command failures'
reject_text "$manual" \
  'sha256sum ~/jenkins-agent-artifacts-bundle.tar.gz' \
  'Native agent checksum must not contain the bundle-factory absolute path'

previous_heading_line=0
for heading in \
  '## 1. Operator Inputs and Preflight' \
  '### 1.1 If You Do Not Have Root Privileges' \
  '## 2. Dependencies and Jenkins Agent Artifact Bundle' \
  '### 2.1 Install Ubuntu Dependencies' \
  '### 2.2 Create the Agent Artifact Bundle' \
  '### 2.3 Stage and Verify the Agent Artifact Bundle' \
  '## 3. Jenkins Agent Installation and Configuration' \
  '### 3.1 Create the Runtime Identity and Product Home' \
  '### 3.2 Confirm the Site-Managed SSH Listener' \
  '### 3.3 Install and Validate the Agent Account SSH Policy' \
  '### 3.4 Enable SSH and Verify Operator Access' \
  '## 4. Jenkins Agent Role-Local Validation' \
  '## 5. Shared Integration Handoff' \
  '## 6. Backup and Operations' \
  '## 7. References'; do
  current_heading_line="$(heading_line "$heading")"
  [ -n "$current_heading_line" ] &&
    [ "$current_heading_line" -gt "$previous_heading_line" ] || {
    printf 'Native agent heading is missing or out of order: %s\n' \
      "$heading" >&2
    exit 1
  }
  previous_heading_line="$current_heading_line"
done

require_text "$manual" \
  'sudo apt update' \
  'Native agent dependency installation must use delegated privilege'
require_text "$manual" \
  'sudo apt install -y' \
  'Native agent package installation must use delegated privilege'
require_text "$manual" \
  'sudo groupadd --gid JENKINS_AGENT_GID jenkins-agent' \
  'Native agent group creation must use the baseline group and reviewed GID'
require_text "$manual" \
  'sudo useradd --uid JENKINS_AGENT_UID --gid JENKINS_AGENT_GID' \
  'Native agent account creation must use the reviewed numeric identity'
require_text "$manual" \
  "sudo usermod -p '*' jenkins-agent" \
  'Native agent account must accept public-key SSH without a password'
require_text "$manual" \
  'jenkins-agent:jenkins-agent' \
  'Native agent ownership checks must use the baseline runtime identity'

require_text "$manual" \
  '/etc/ssh/sshd_config.d/40-jenkins-agent.conf' \
  'Native agent procedure must install the selected role-owned SSH policy'
reject_text "$manual" \
  '/etc/ssh/sshd_config.d/40-loopforge-jenkins-agent.conf' \
  'Native agent SSH policy filename must not include the product name'
require_text "$manual" \
  $'# Port and ListenAddress are site-owned.\nMatch User jenkins-agent\n    AuthenticationMethods publickey\n    PubkeyAuthentication yes\n    PasswordAuthentication no\n    KbdInteractiveAuthentication no\n    PermitEmptyPasswords no\nMatch all' \
  'Native agent SSH fragment must be account-scoped and public-key only'
if grep -Eq '^[[:space:]]*(Port|ListenAddress|AllowUsers)[[:space:]]' "$manual"; then
  printf 'Native agent role must not install global listener or allow-list directives\n' >&2
  exit 1
fi
require_text "$manual" \
  'sudo sshd -t' \
  'Native agent procedure must syntax-check effective sshd configuration'
require_text "$manual" \
  'sudo sshd -T -C' \
  'Native agent procedure must inspect account-specific effective SSH policy'
require_text "$manual" \
  'site SSH/network provisioning stop condition' \
  'Native agent procedure must fail clearly for a missing site listener'
require_text "$manual" \
  'sudo systemctl enable --now ssh' \
  'Native agent procedure must enable and start the Ubuntu SSH service'
require_text "$manual" \
  'sudo systemctl reload ssh' \
  'Native agent procedure must load the validated account policy'

listener_section="$(
  sed -n \
    '/^### 3\.2 Confirm the Site-Managed SSH Listener$/,/^### 3\.3 Install and Validate the Agent Account SSH Policy$/p' \
    "$manual"
)"
for listener_check in \
  'sudo sshd -T' \
  'JENKINS_AGENT_SSH_PORT' \
  'site SSH/network provisioning stop condition'; do
  grep -Fq -- "$listener_check" <<<"$listener_section" || {
    printf 'Native agent listener checkpoint is missing: %s\n' \
      "$listener_check" >&2
    exit 1
  }
done
for listener_mutation in 'sudoedit' '/etc/ssh/sshd_config.d/' 'systemctl'; do
  if grep -Fq -- "$listener_mutation" <<<"$listener_section"; then
    printf 'Native agent listener review must not mutate state: %s\n' \
      "$listener_mutation" >&2
    exit 1
  fi
done

policy_section="$(
  sed -n \
    '/^### 3\.3 Install and Validate the Agent Account SSH Policy$/,/^### 3\.4 Enable SSH and Verify Operator Access$/p' \
    "$manual"
)"
for policy_check in \
  'sudoedit /etc/ssh/sshd_config.d/40-jenkins-agent.conf' \
  'sudo chown root:root /etc/ssh/sshd_config.d/40-jenkins-agent.conf' \
  'sudo chmod 0644 /etc/ssh/sshd_config.d/40-jenkins-agent.conf' \
  'sudo sshd -t' \
  'sudo sshd -T -C'; do
  grep -Fq -- "$policy_check" <<<"$policy_section" || {
    printf 'Native agent policy checkpoint is missing: %s\n' \
      "$policy_check" >&2
    exit 1
  }
done
if grep -Fq -- 'systemctl' <<<"$policy_section"; then
  printf 'Native agent policy validation must precede SSH service mutation\n' >&2
  exit 1
fi

service_section="$(
  sed -n \
    '/^### 3\.4 Enable SSH and Verify Operator Access$/,/^## 4\. Jenkins Agent Role-Local Validation$/p' \
    "$manual"
)"
for service_check in \
  'sudo systemctl enable --now ssh' \
  'sudo systemctl reload ssh' \
  'second operator login'; do
  grep -Fq -- "$service_check" <<<"$service_section" || {
    printf 'Native agent SSH service checkpoint is missing: %s\n' \
      "$service_check" >&2
    exit 1
  }
done
if grep -Fq -- 'sudoedit /etc/ssh/sshd_config.d/' <<<"$service_section"; then
  printf 'Native agent SSH service checkpoint must not create policy state\n' >&2
  exit 1
fi

for validation_check in \
  'systemctl is-enabled ssh' \
  'systemctl is-active ssh' \
  '--property=ActiveState --property=MainPID --no-pager' \
  'ssh-keyscan -T 5 -p JENKINS_AGENT_SSH_PORT JENKINS_AGENT_HOST' \
  'sudo systemctl status ssh --no-pager --lines=20'; do
  require_text "$manual" "$validation_check" \
    "Native agent validation is missing: $validation_check"
done

validation_section="$(
  sed -n '/^## 4\. Jenkins Agent Role-Local Validation$/,/^## 5\. Shared Integration Handoff$/p' \
    "$manual"
)"
for replayed_operation in \
  'sha256sum' \
  'getent passwd' \
  'getent group' \
  'getent shadow' \
  'stat -c' \
  'sshd -t' \
  'sshd -T'; do
  if grep -Fq -- "$replayed_operation" <<<"$validation_section"; then
    printf 'Native agent validation must not replay earlier operation: %s\n' \
      "$replayed_operation" >&2
    exit 1
  fi
done
require_text "$manual" \
  'Do not replay those earlier checkpoint operations' \
  'Native agent validation must preserve earlier checkpoint ownership'

require_text "$prd" \
  'OS dependency provisioning is a separate' \
  'PRD must separate OS dependency provisioning from application artifacts'
require_text "$prd" \
  'before runtime identity, product-home, application, or service mutation' \
  'PRD must define the application artifact mutation gate precisely'
require_text "$system_model" \
  'This prerequisite provisioning may occur before application' \
  'System model must allow dependency-first provisioning'
require_text "$lifecycle" \
  'not replay their setup or verification operations' \
  'Lifecycle contract must preserve completed checkpoint ownership'
require_text "$setup_manual" \
  'completed artifact, identity,' \
  'Jenkins agent manual must compose readiness from owned checkpoints'
require_text "$lifecycle" \
  'This checkpoint changes staging only; role setup owns' \
  'Lifecycle contract must separate staging from role-local runtime mutation'
require_text "$operator_contract" \
  'OS dependency provisioning' \
  'Operator contract must distinguish OS dependency provisioning'
require_text "$review_guide" \
  'Do not replay completed checkpoint operations during role validation.' \
  'Native review guide must reject validation replay'
require_text "$step_plan" \
  'Validation must not replay completed checkpoint' \
  'Jenkins agent step plan must preserve validation ownership'

apt_line="$(grep -n -m1 'sudo apt update' "$manual" | cut -d: -f1)"
bundle_line="$(heading_line '### 2.2 Create the Agent Artifact Bundle')"
stage_line="$(grep -n -m1 'sha256sum -c jenkins-agent-artifacts-bundle.tar.gz.sha256' "$manual" | cut -d: -f1)"
identity_line="$(grep -n -m1 'sudo groupadd --gid JENKINS_AGENT_GID jenkins-agent' "$manual" | cut -d: -f1)"
listener_line="$(heading_line '### 3.2 Confirm the Site-Managed SSH Listener')"
policy_line="$(grep -n -m1 'sudoedit /etc/ssh/sshd_config.d/40-jenkins-agent.conf' "$manual" | cut -d: -f1)"
policy_validation_line="$(grep -n -m1 'sudo sshd -t' "$manual" | cut -d: -f1)"
service_line="$(grep -n -m1 'sudo systemctl enable --now ssh' "$manual" | cut -d: -f1)"
validation_line="$(heading_line '## 4. Jenkins Agent Role-Local Validation')"
handoff_line="$(heading_line '## 5. Shared Integration Handoff')"
[ "$apt_line" -lt "$bundle_line" ] &&
  [ "$bundle_line" -lt "$stage_line" ] &&
  [ "$stage_line" -lt "$identity_line" ] &&
  [ "$identity_line" -lt "$listener_line" ] &&
  [ "$listener_line" -lt "$policy_line" ] &&
  [ "$policy_line" -lt "$policy_validation_line" ] &&
  [ "$policy_validation_line" -lt "$service_line" ] &&
  [ "$service_line" -lt "$validation_line" ] &&
  [ "$validation_line" -lt "$handoff_line" ] || {
  printf 'Native agent lifecycle operations are out of order\n' >&2
  exit 1
}

require_text "$manual" \
  'Complete Section 4 before controller-to-agent integration.' \
  'Native agent handoff must require role-local validation'

require_text "$integration" \
  '| Jenkins agent runtime group | `jenkins-agent`, local OS group |' \
  'Native integration must inventory the baseline agent runtime group'
for integration_pattern in \
  '-o jenkins-agent -g jenkins-agent' \
  'jenkins-agent:jenkins-agent' \
  'jenkins-agent@JENKINS_AGENT_HOST' \
  'sudo usermod -a -G jenkins-share jenkins-agent' \
  'sudo -u jenkins-agent'; do
  require_text "$integration" "$integration_pattern" \
    "Native integration must consume reviewed agent identity: $integration_pattern"
done

require_text "$manual" \
  'Do not reinstall the artifact bundle to repair an account, key, product home,' \
  'Native agent recovery must not claim that artifacts repair runtime state'
require_text "$manual" \
  'reprovision a fresh agent target' \
  'Native agent recovery must require explicit fresh-state reprovisioning'
require_text "$manual" \
  'are site-owned administration outside Loopforge v1 setup.' \
  'Native agent recovery must leave key rotation outside v1 setup'

printf 'Native Jenkins agent documentation contract passed\n'
